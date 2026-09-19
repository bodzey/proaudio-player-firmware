use std::fs;
use std::net::IpAddr;

pub const CONFIG_PATH: &str = "/etc/proaudio-networkd.conf";

#[derive(Clone, Debug)]
pub struct Config {
    pub wifi_iface: String,
    pub setup_ssid_prefix: String,
    pub setup_password: String,
    pub setup_address: String,
    pub setup_prefix: u8,
    pub setup_dhcp_start: String,
    pub setup_dhcp_end: String,
    pub setup_channel: u8,
    pub setup_timeout: u64,
    pub regdomain: String,
    pub gpio_chip: String,
    pub gpio_line: u32,
    pub gpio_hold_seconds: f64,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            wifi_iface: "auto".into(),
            setup_ssid_prefix: "ProAudio-Player".into(),
            setup_password: "proaudio-setup".into(),
            setup_address: "192.168.4.1".into(),
            setup_prefix: 24,
            setup_dhcp_start: "192.168.4.20".into(),
            setup_dhcp_end: "192.168.4.100".into(),
            setup_channel: 6,
            setup_timeout: 600,
            regdomain: "UA".into(),
            gpio_chip: "/dev/gpiochip0".into(),
            gpio_line: 26,
            gpio_hold_seconds: 5.0,
        }
    }
}

impl Config {
    pub fn load(path: &str) -> Result<Self, String> {
        let mut config = Self::default();
        let input = match fs::read_to_string(path) {
            Ok(value) => value,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(config),
            Err(error) => return Err(format!("cannot read {path}: {error}")),
        };

        for raw in input.lines() {
            let line = raw.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let Some((key, raw_value)) = line.split_once('=') else {
                continue;
            };
            let value = raw_value
                .trim()
                .trim_matches(|character| character == '\'' || character == '"');
            match key.trim() {
                "WIFI_IFACE" => config.wifi_iface = value.into(),
                "SETUP_SSID_PREFIX" => config.setup_ssid_prefix = value.into(),
                "SETUP_PASSWORD" => config.setup_password = value.into(),
                "SETUP_ADDRESS" => config.setup_address = value.into(),
                "SETUP_PREFIX" => config.setup_prefix = parse(value, "SETUP_PREFIX")?,
                "SETUP_DHCP_START" => config.setup_dhcp_start = value.into(),
                "SETUP_DHCP_END" => config.setup_dhcp_end = value.into(),
                "SETUP_CHANNEL" => config.setup_channel = parse(value, "SETUP_CHANNEL")?,
                "SETUP_TIMEOUT" => config.setup_timeout = parse(value, "SETUP_TIMEOUT")?,
                "REGDOMAIN" => config.regdomain = value.to_ascii_uppercase(),
                "GPIO_CHIP" => config.gpio_chip = value.into(),
                "GPIO_LINE" => config.gpio_line = parse(value, "GPIO_LINE")?,
                "GPIO_HOLD_SECONDS" => {
                    config.gpio_hold_seconds = parse(value, "GPIO_HOLD_SECONDS")?
                }
                _ => {}
            }
        }

        if config.setup_prefix > 32 {
            return Err("SETUP_PREFIX must be between 0 and 32".into());
        }
        if config.setup_channel == 0 || config.setup_channel > 14 {
            return Err("SETUP_CHANNEL must be between 1 and 14".into());
        }
        if config.regdomain.len() != 2
            || !config
                .regdomain
                .bytes()
                .all(|character| character.is_ascii_alphabetic())
        {
            return Err("REGDOMAIN must be a two-letter country code".into());
        }
        if !valid_wpa_psk(&config.setup_password) {
            return Err(
                "SETUP_PASSWORD must be 8-63 UTF-8 bytes or exactly 64 hexadecimal characters"
                    .into(),
            );
        }
        config
            .setup_address
            .parse::<IpAddr>()
            .map_err(|_| "SETUP_ADDRESS must be an IP address".to_string())?;
        Ok(config)
    }
}

fn parse<T: std::str::FromStr>(value: &str, key: &str) -> Result<T, String> {
    value.parse().map_err(|_| format!("invalid {key}: {value}"))
}

fn valid_wpa_psk(value: &str) -> bool {
    let bytes = value.as_bytes();
    (8..=63).contains(&bytes.len())
        || (bytes.len() == 64 && bytes.iter().all(u8::is_ascii_hexdigit))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_match_appliance_contract() {
        let config = Config::default();
        assert_eq!(config.setup_ssid_prefix, "ProAudio-Player");
        assert_eq!(config.setup_address, "192.168.4.1");
        assert_eq!(config.setup_password, "proaudio-setup");
        assert_eq!(config.gpio_line, 26);
        assert_eq!(config.regdomain, "UA");
    }

    #[test]
    fn setup_password_requires_wpa_psk_strength() {
        assert!(valid_wpa_psk("proaudio-setup"));
        assert!(valid_wpa_psk(
            "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        ));
        assert!(!valid_wpa_psk(""));
        assert!(!valid_wpa_psk("short"));
    }
}
