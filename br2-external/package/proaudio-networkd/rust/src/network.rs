use std::collections::{HashMap, HashSet};
use std::fs;
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

use crate::config::Config;
use crate::process::{run, split_nmcli_escaped, CommandResult};
use crate::signals;
use crate::state::{SharedState, WifiNetwork};

const WIFI_PROFILE: &str = "proaudio-wifi";
const SETUP_PROFILE: &str = "proaudio-setup";

pub struct NetworkDaemon {
    config: Config,
    iface: String,
    shared: Arc<Mutex<SharedState>>,
    dnsmasq: Option<Child>,
}

impl NetworkDaemon {
    pub fn new(config: Config, shared: Arc<Mutex<SharedState>>) -> Self {
        Self {
            config,
            iface: String::new(),
            shared,
            dnsmasq: None,
        }
    }

    pub fn interface(&self) -> &str {
        &self.iface
    }

    pub fn set_interface(&mut self, iface: String) {
        self.iface = iface;
    }

    fn nmcli(&self, args: &[&str], timeout: Duration) -> CommandResult {
        run("/usr/bin/nmcli", args, timeout)
    }

    pub fn enable_wifi(&self) {
        let _ = self.nmcli(&["radio", "wifi", "on"], Duration::from_secs(10));
    }

    pub fn wait_for_networkmanager(&self) -> bool {
        let deadline = Instant::now() + Duration::from_secs(45);
        while Instant::now() < deadline && !signals::stop_requested() {
            let result = self.nmcli(&["-t", "-f", "RUNNING", "general"], Duration::from_secs(5));
            if result.success() && result.stdout.to_ascii_lowercase().contains("running") {
                return true;
            }
            thread::sleep(Duration::from_secs(1));
        }
        false
    }

    pub fn find_wifi_interface(&self) -> Option<String> {
        if self.config.wifi_iface != "auto" {
            return Some(self.config.wifi_iface.clone());
        }
        let result = self.nmcli(
            &["-t", "-e", "yes", "-f", "DEVICE,TYPE", "device", "status"],
            Duration::from_secs(10),
        );
        if !result.success() {
            return None;
        }
        result.stdout.lines().find_map(|line| {
            let fields = split_nmcli_escaped(line);
            (fields.len() >= 2 && fields[1] == "wifi").then(|| fields[0].clone())
        })
    }

    pub fn configure_regdomain(&self) {
        let result = run(
            "/usr/sbin/iw",
            &["reg", "set", &self.config.regdomain],
            Duration::from_secs(5),
        );
        if !result.success() {
            eprintln!(
                "WARN cannot set regulatory domain {}: {}",
                self.config.regdomain,
                result.message()
            );
        }
    }

    fn device_serial_suffix(&self) -> String {
        let serial = fs::read_to_string("/proc/cpuinfo")
            .ok()
            .and_then(|content| {
                content.lines().find_map(|line| {
                    let (key, value) = line.split_once(':')?;
                    key.trim()
                        .eq_ignore_ascii_case("serial")
                        .then(|| value.trim().to_string())
                })
            })
            .filter(|value| !value.is_empty())
            .or_else(|| {
                fs::read_to_string("/etc/machine-id")
                    .ok()
                    .map(|value| value.trim().to_string())
            })
            .unwrap_or_else(|| "0000".into());
        let cleaned: String = serial
            .chars()
            .filter(|character| character.is_ascii_alphanumeric())
            .map(|character| character.to_ascii_uppercase())
            .collect();
        let suffix = if cleaned.len() > 4 {
            &cleaned[cleaned.len() - 4..]
        } else {
            cleaned.as_str()
        };
        format!("{suffix:0>4}")
    }

    pub fn setup_ssid(&self) -> String {
        let prefix = if self.config.setup_ssid_prefix.trim().is_empty() {
            "ProAudio-Player"
        } else {
            self.config.setup_ssid_prefix.trim()
        };
        format!("{prefix}-{}", self.device_serial_suffix())
    }

    pub fn configure_hostname(&self) {
        let wanted = format!(
            "proaudio-player-{}",
            self.device_serial_suffix().to_ascii_lowercase()
        );
        let current = run("/bin/hostname", &[], Duration::from_secs(5));
        if current.success() && current.stdout.trim() == wanted {
            return;
        }
        let result = run("/bin/hostname", &[&wanted], Duration::from_secs(5));
        if result.success() {
            eprintln!("INFO runtime hostname: {wanted}");
        } else {
            eprintln!(
                "WARN cannot set runtime hostname {wanted}: {}",
                result.message()
            );
        }
    }

    fn default_route_interfaces(&self) -> HashSet<String> {
        let Ok(routes) = fs::read_to_string("/proc/net/route") else {
            return HashSet::new();
        };
        routes
            .lines()
            .skip(1)
            .filter_map(|line| {
                let fields: Vec<_> = line.split_whitespace().collect();
                if fields.len() < 4 || fields[1] != "00000000" {
                    return None;
                }
                let flags = u32::from_str_radix(fields[3], 16).ok()?;
                (flags & 1 != 0).then(|| fields[0].to_string())
            })
            .collect()
    }

    pub fn setup_active(&self) -> bool {
        self.shared.lock().expect("state poisoned").setup_active
    }

    pub fn has_network_connection(&self) -> bool {
        let mut interfaces = self.default_route_interfaces();
        if self.setup_active() {
            interfaces.remove(&self.iface);
        }
        !interfaces.is_empty()
    }

    pub fn ethernet_connected(&self) -> bool {
        self.default_route_interfaces()
            .into_iter()
            .any(|interface| interface != self.iface)
    }

    pub fn wifi_profile_exists(&self) -> bool {
        let result = self.nmcli(
            &["-t", "-f", "NAME", "connection", "show", WIFI_PROFILE],
            Duration::from_secs(10),
        );
        result.success() && result.stdout.lines().any(|line| line == WIFI_PROFILE)
    }

    pub fn set_wifi_standby(&mut self, standby: bool) {
        if self.setup_active() {
            self.stop_ap();
        }
        if !self.wifi_profile_exists() {
            if standby {
                let _ = self.nmcli(
                    &["device", "disconnect", &self.iface],
                    Duration::from_secs(10),
                );
            }
            return;
        }
        let _ = self.nmcli(
            &[
                "connection",
                "modify",
                WIFI_PROFILE,
                "connection.autoconnect",
                if standby { "no" } else { "yes" },
            ],
            Duration::from_secs(10),
        );
        if standby {
            let _ = self.nmcli(
                &["connection", "down", WIFI_PROFILE],
                Duration::from_secs(15),
            );
            let _ = self.nmcli(
                &["device", "disconnect", &self.iface],
                Duration::from_secs(10),
            );
            eprintln!("INFO Ethernet active; Wi-Fi moved to standby");
            return;
        }
        let result = self.nmcli(
            &[
                "--wait",
                "25",
                "connection",
                "up",
                WIFI_PROFILE,
                "ifname",
                &self.iface,
            ],
            Duration::from_secs(30),
        );
        if result.success() {
            eprintln!("INFO Wi-Fi connection restored");
        } else {
            eprintln!("WARN cannot restore Wi-Fi: {}", result.message());
        }
    }

    pub fn scan(&self) {
        self.enable_wifi();
        self.configure_regdomain();
        let result = self.nmcli(
            &[
                "-t",
                "-e",
                "yes",
                "-f",
                "SSID,SIGNAL,SECURITY",
                "device",
                "wifi",
                "list",
                "ifname",
                &self.iface,
                "--rescan",
                "auto",
            ],
            Duration::from_secs(20),
        );
        if !result.success() {
            eprintln!("WARN Wi-Fi scan failed: {}", result.message());
            return;
        }

        let setup_ssid = self.setup_ssid();
        let mut found: HashMap<String, WifiNetwork> = HashMap::new();
        for line in result.stdout.lines() {
            let fields = split_nmcli_escaped(line);
            if fields.len() < 3 {
                continue;
            }
            let ssid = fields[0].trim().to_string();
            if ssid.is_empty() || ssid == setup_ssid {
                continue;
            }
            let signal = fields[1].parse::<i32>().unwrap_or(0);
            let security = if fields[2].trim().is_empty() {
                "Open".to_string()
            } else {
                fields[2].trim().to_string()
            };
            let replace = found
                .get(&ssid)
                .map(|previous| signal > previous.signal)
                .unwrap_or(true);
            if replace {
                found.insert(
                    ssid.clone(),
                    WifiNetwork {
                        ssid,
                        signal,
                        security,
                    },
                );
            }
        }

        let mut networks: Vec<_> = found.into_values().collect();
        networks.sort_by(|left, right| {
            right
                .signal
                .cmp(&left.signal)
                .then_with(|| left.ssid.to_lowercase().cmp(&right.ssid.to_lowercase()))
        });
        let count = networks.len();
        self.shared.lock().expect("state poisoned").networks = networks;
        eprintln!("INFO found {count} Wi-Fi networks");
    }

    fn delete_connection(&self, name: &str) {
        let _ = self.nmcli(&["connection", "delete", name], Duration::from_secs(10));
    }

    fn start_dnsmasq(&mut self) -> Result<(), String> {
        self.stop_dnsmasq();
        let mask = prefix_to_mask(self.config.setup_prefix)?;
        let range = format!(
            "{},{},{},10m",
            self.config.setup_dhcp_start, self.config.setup_dhcp_end, mask
        );
        let router = format!("3,{}", self.config.setup_address);
        let dns = format!("6,{}", self.config.setup_address);
        let captive = format!("114,http://{}/", self.config.setup_address);
        let wildcard = format!("/#/{}", self.config.setup_address);
        let listen = format!("--listen-address={}", self.config.setup_address);
        let interface = format!("--interface={}", self.iface);
        let range_arg = format!("--dhcp-range={range}");
        let router_arg = format!("--dhcp-option={router}");
        let dns_arg = format!("--dhcp-option={dns}");
        let captive_arg = format!("--dhcp-option={captive}");
        let wildcard_arg = format!("--address={wildcard}");

        let mut child = Command::new("/usr/sbin/dnsmasq")
            .args([
                "--no-daemon",
                "--conf-file=/dev/null",
                &interface,
                "--bind-interfaces",
                &listen,
                &range_arg,
                &router_arg,
                &dns_arg,
                &captive_arg,
                &wildcard_arg,
                "--dhcp-leasefile=/run/proaudio-networkd.leases",
                "--no-resolv",
                "--no-hosts",
            ])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|error| format!("cannot start dnsmasq: {error}"))?;
        thread::sleep(Duration::from_millis(250));
        if child
            .try_wait()
            .map_err(|error| error.to_string())?
            .is_some()
        {
            return Err("dnsmasq exited during startup".into());
        }
        self.dnsmasq = Some(child);
        Ok(())
    }

    fn stop_dnsmasq(&mut self) {
        if let Some(mut child) = self.dnsmasq.take() {
            let _ = child.kill();
            let _ = child.wait();
        }
    }

    pub fn start_ap(&mut self) -> Result<(), String> {
        self.stop_dnsmasq();
        self.delete_connection(SETUP_PROFILE);
        let ssid = self.setup_ssid();
        let result = self.nmcli(
            &[
                "connection",
                "add",
                "type",
                "wifi",
                "ifname",
                &self.iface,
                "con-name",
                SETUP_PROFILE,
                "ssid",
                &ssid,
            ],
            Duration::from_secs(15),
        );
        if !result.success() {
            return Err(format!(
                "cannot create setup Wi-Fi profile: {}",
                result.message()
            ));
        }

        let address = format!("{}/{}", self.config.setup_address, self.config.setup_prefix);
        let channel = self.config.setup_channel.to_string();
        let mut args = vec![
            "connection",
            "modify",
            SETUP_PROFILE,
            "connection.autoconnect",
            "no",
            "802-11-wireless.mode",
            "ap",
            "802-11-wireless.band",
            "bg",
            "802-11-wireless.channel",
            &channel,
            "802-11-wireless.powersave",
            "2",
            "ipv4.method",
            "manual",
            "ipv4.addresses",
            &address,
            "ipv4.never-default",
            "yes",
            "ipv6.method",
            "disabled",
        ];
        if !self.config.setup_password.is_empty() {
            args.extend_from_slice(&[
                "802-11-wireless-security.key-mgmt",
                "wpa-psk",
                "802-11-wireless-security.proto",
                "rsn",
                "802-11-wireless-security.psk",
                &self.config.setup_password,
            ]);
        }
        let result = self.nmcli(&args, Duration::from_secs(15));
        if !result.success() {
            self.delete_connection(SETUP_PROFILE);
            return Err(format!(
                "cannot configure setup Wi-Fi profile: {}",
                result.message()
            ));
        }
        let result = self.nmcli(
            &[
                "--wait",
                "20",
                "connection",
                "up",
                SETUP_PROFILE,
                "ifname",
                &self.iface,
            ],
            Duration::from_secs(25),
        );
        if !result.success() {
            self.delete_connection(SETUP_PROFILE);
            return Err(format!("cannot start setup hotspot: {}", result.message()));
        }

        self.start_dnsmasq()?;
        self.shared.lock().expect("state poisoned").setup_active = true;
        eprintln!(
            "INFO setup AP active: SSID={ssid}, portal=http://{}/",
            self.config.setup_address
        );
        Ok(())
    }

    pub fn stop_ap(&mut self) {
        self.shared.lock().expect("state poisoned").setup_active = false;
        self.stop_dnsmasq();
        if !self.iface.is_empty() {
            let _ = self.nmcli(
                &["connection", "down", SETUP_PROFILE],
                Duration::from_secs(10),
            );
            self.delete_connection(SETUP_PROFILE);
        }
    }

    fn wifi_cache_contains(&self, ssid: &str) -> bool {
        let result = self.nmcli(
            &[
                "-t",
                "-e",
                "yes",
                "-f",
                "SSID",
                "device",
                "wifi",
                "list",
                "ifname",
                &self.iface,
                "--rescan",
                "no",
            ],
            Duration::from_secs(10),
        );
        result.success()
            && result
                .stdout
                .lines()
                .filter(|line| !line.is_empty())
                .any(|line| {
                    split_nmcli_escaped(line)
                        .first()
                        .map(|value| value == ssid)
                        .unwrap_or(false)
                })
    }

    fn prepare_station_connection(&mut self, ssid: &str) -> bool {
        self.stop_ap();
        self.enable_wifi();
        self.configure_regdomain();
        thread::sleep(Duration::from_millis(750));

        for attempt in 0..3 {
            let result = self.nmcli(
                &[
                    "device",
                    "wifi",
                    "rescan",
                    "ifname",
                    &self.iface,
                    "ssid",
                    ssid,
                ],
                Duration::from_secs(12),
            );
            if result.success() {
                let deadline = Instant::now() + Duration::from_secs(4);
                while Instant::now() < deadline {
                    if self.wifi_cache_contains(ssid) {
                        return true;
                    }
                    thread::sleep(Duration::from_millis(400));
                }
            } else {
                eprintln!(
                    "INFO directed Wi-Fi scan for {ssid} attempt {}/3 deferred: {}",
                    attempt + 1,
                    result.message()
                );
            }
            thread::sleep(Duration::from_millis(750 * (attempt + 1) as u64));
        }
        self.wifi_cache_contains(ssid)
    }

    pub fn connect_wifi(&mut self, ssid: &str, password: &str) -> bool {
        {
            let mut state = self.shared.lock().expect("state poisoned");
            state.connecting = true;
            state.last_error.clear();
        }
        thread::sleep(Duration::from_secs(1));

        let visible = self.prepare_station_connection(ssid);
        self.delete_connection(WIFI_PROFILE);
        let mut args = vec![
            "--wait",
            "30",
            "device",
            "wifi",
            "connect",
            ssid,
            "ifname",
            &self.iface,
            "name",
            WIFI_PROFILE,
        ];
        if !password.is_empty() {
            args.extend_from_slice(&["password", password]);
        }
        if !visible {
            args.extend_from_slice(&["hidden", "yes"]);
        }
        let result = self.nmcli(&args, Duration::from_secs(40));

        let success = if result.success() {
            let _ = self.nmcli(
                &[
                    "connection",
                    "modify",
                    WIFI_PROFILE,
                    "connection.autoconnect",
                    "yes",
                    "connection.autoconnect-priority",
                    "100",
                    "802-11-wireless.powersave",
                    "2",
                ],
                Duration::from_secs(10),
            );
            eprintln!("INFO Wi-Fi provisioning successful: SSID={ssid}");
            true
        } else {
            eprintln!(
                "WARN Wi-Fi provisioning failed for {ssid}: {}",
                result.message()
            );
            self.delete_connection(WIFI_PROFILE);
            self.shared.lock().expect("state poisoned").last_error = format!(
                "Не вдалося підключитися до «{ssid}». Перевірте пароль і спробуйте ще раз."
            );
            if let Err(error) = self.start_ap() {
                eprintln!("ERROR cannot restore setup hotspot: {error}");
            }
            false
        };

        self.shared.lock().expect("state poisoned").connecting = false;
        success
    }
}

fn prefix_to_mask(prefix: u8) -> Result<String, String> {
    if prefix > 32 {
        return Err("IPv4 prefix exceeds 32".into());
    }
    let mask = if prefix == 0 {
        0
    } else {
        u32::MAX << (32 - prefix)
    };
    Ok(format!(
        "{}.{}.{}.{}",
        (mask >> 24) & 0xff,
        (mask >> 16) & 0xff,
        (mask >> 8) & 0xff,
        mask & 0xff
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn converts_prefix_to_ipv4_netmask() {
        assert_eq!(prefix_to_mask(24).unwrap(), "255.255.255.0");
        assert_eq!(prefix_to_mask(0).unwrap(), "0.0.0.0");
        assert!(prefix_to_mask(33).is_err());
    }
}
