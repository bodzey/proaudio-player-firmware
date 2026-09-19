mod config;
mod gpio;
mod network;
mod portal;
mod process;
mod signals;
mod state;

use std::sync::{mpsc, Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

use config::{Config, CONFIG_PATH};
use network::NetworkDaemon;
use state::{ControlMessage, SharedState};

struct SetupSession {
    deadline: Option<Instant>,
    stop_when_online: bool,
}

fn main() {
    signals::install();
    if let Err(error) = run() {
        eprintln!("ERROR {error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let config = Config::load(CONFIG_PATH)?;
    let shared = Arc::new(Mutex::new(SharedState::default()));
    let (tx, rx) = mpsc::channel();
    let mut daemon = NetworkDaemon::new(config.clone(), Arc::clone(&shared));

    if !daemon.wait_for_networkmanager() {
        return Err("NetworkManager is not ready".into());
    }
    daemon.configure_hostname();
    daemon.enable_wifi();
    daemon.configure_regdomain();

    for _ in 0..30 {
        if let Some(interface) = daemon.find_wifi_interface() {
            daemon.set_interface(interface);
            break;
        }
        if signals::stop_requested() {
            return Ok(());
        }
        thread::sleep(Duration::from_secs(1));
    }
    if daemon.interface().is_empty() {
        return Err("Wi-Fi interface not found".into());
    }
    eprintln!("INFO Wi-Fi interface: {}", daemon.interface());

    let setup_ssid = daemon.setup_ssid();
    let http_thread = portal::start(
        config.clone(),
        Arc::clone(&shared),
        tx.clone(),
        setup_ssid,
    )?;
    gpio::start(config.clone(), tx.clone());

    let mut setup: Option<SetupSession> = None;
    let mut offline_since: Option<Instant> = None;
    let mut ethernet_was_connected: Option<bool> = None;
    let setup_timeout = Duration::from_secs(config.setup_timeout.max(60));
    let mut saved_profile_offline_logged = false;

    while !signals::stop_requested() {
        if signals::take_setup_request() {
            let _ = tx.send(ControlMessage::Setup);
        }

        let ethernet_connected = daemon.ethernet_connected();
        if ethernet_was_connected != Some(ethernet_connected) {
            daemon.set_wifi_standby(ethernet_connected);
            ethernet_was_connected = Some(ethernet_connected);
            if ethernet_connected {
                setup = None;
            }
        }

        while let Ok(message) = rx.try_recv() {
            match message {
                ControlMessage::Setup => {
                    if ethernet_connected {
                        eprintln!("INFO Setup Mode skipped because Ethernet is active");
                        continue;
                    }
                    eprintln!("INFO forced Setup Mode");
                    daemon.scan();
                    daemon.start_ap()?;
                    setup = Some(SetupSession {
                        deadline: Some(Instant::now() + setup_timeout),
                        stop_when_online: false,
                    });
                    offline_since = None;
                }
                ControlMessage::Connect { ssid, password } => {
                    if !daemon.setup_active() {
                        shared.lock().expect("state poisoned").connecting = false;
                        continue;
                    }
                    if daemon.connect_wifi(&ssid, &password) {
                        setup = None;
                        offline_since = None;
                        saved_profile_offline_logged = false;
                    }
                }
            }
        }

        if let Some(session) = setup.as_ref() {
            if ethernet_connected || (session.stop_when_online && daemon.has_network_connection()) {
                eprintln!("INFO network connectivity restored; leaving Setup Mode");
                daemon.stop_ap();
                setup = None;
                offline_since = None;
                continue;
            }
            if session
                .deadline
                .is_some_and(|deadline| Instant::now() >= deadline)
            {
                eprintln!("INFO Setup Mode timeout");
                daemon.stop_ap();
                setup = None;
                offline_since = None;
                continue;
            }
        } else if daemon.has_network_connection() {
            offline_since = None;
            saved_profile_offline_logged = false;
        } else {
            let since = *offline_since.get_or_insert_with(|| {
                eprintln!("INFO network unavailable; waiting before Setup Mode");
                Instant::now()
            });
            if since.elapsed() >= Duration::from_secs(15) {
                if daemon.wifi_profile_exists() {
                    if !saved_profile_offline_logged {
                        eprintln!("WARN saved Wi-Fi profile is offline; automatic provisioning is suppressed, hold the setup button to reconfigure");
                        saved_profile_offline_logged = true;
                    }
                    offline_since = Some(Instant::now());
                } else {
                    eprintln!("INFO no saved Wi-Fi profile; starting initial Setup Mode");
                    daemon.scan();
                    daemon.start_ap()?;
                    setup = Some(SetupSession {
                        deadline: None,
                        stop_when_online: true,
                    });
                    offline_since = None;
                }
            }
        }

        thread::sleep(Duration::from_millis(250));
    }

    daemon.stop_ap();
    signals::request_stop();
    let _ = http_thread.join();
    Ok(())
}
