#[derive(Clone, Debug)]
pub struct WifiNetwork {
    pub ssid: String,
    pub signal: i32,
    pub security: String,
}

#[derive(Default)]
pub struct SharedState {
    pub setup_active: bool,
    pub networks: Vec<WifiNetwork>,
    pub last_error: String,
    pub connecting: bool,
}

pub enum ControlMessage {
    Connect { ssid: String, password: String },
    Setup,
}
