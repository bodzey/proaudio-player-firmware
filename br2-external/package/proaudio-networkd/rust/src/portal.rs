use std::collections::HashMap;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{IpAddr, TcpListener, TcpStream};
use std::sync::{mpsc, Arc, Mutex};
use std::thread;
use std::time::Duration;

use crate::config::Config;
use crate::signals;
use crate::state::{ControlMessage, SharedState};

const PLAYER_PORT: u16 = 8080;
const PORTAL_PORT: u16 = 80;

pub fn start(
    config: Config,
    shared: Arc<Mutex<SharedState>>,
    tx: mpsc::Sender<ControlMessage>,
    setup_ssid: String,
) -> Result<thread::JoinHandle<()>, String> {
    let listener = TcpListener::bind(("0.0.0.0", PORTAL_PORT))
        .map_err(|error| format!("cannot bind portal port {PORTAL_PORT}: {error}"))?;
    listener
        .set_nonblocking(true)
        .map_err(|error| error.to_string())?;

    Ok(thread::spawn(move || {
        eprintln!("INFO HTTP gateway active on port {PORTAL_PORT}");
        while !signals::stop_requested() {
            match listener.accept() {
                Ok((stream, _)) => {
                    let config = config.clone();
                    let shared = Arc::clone(&shared);
                    let tx = tx.clone();
                    let setup_ssid = setup_ssid.clone();
                    thread::spawn(move || {
                        handle_client(stream, &config, &shared, &tx, &setup_ssid)
                    });
                }
                Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                    thread::sleep(Duration::from_millis(100));
                }
                Err(error) => {
                    eprintln!("WARN portal accept failed: {error}");
                    thread::sleep(Duration::from_millis(250));
                }
            }
        }
    }))
}

fn handle_client(
    mut stream: TcpStream,
    config: &Config,
    shared: &Arc<Mutex<SharedState>>,
    tx: &mpsc::Sender<ControlMessage>,
    setup_ssid: &str,
) {
    let _ = stream.set_read_timeout(Some(Duration::from_secs(3)));
    let local_ip = stream.local_addr().ok().map(|address| address.ip());
    let Ok(reader_stream) = stream.try_clone() else {
        return;
    };
    let mut reader = BufReader::new(reader_stream);

    let mut request_line = String::new();
    if reader.read_line(&mut request_line).is_err() || request_line.len() > 2048 {
        return;
    }
    let mut parts = request_line.split_whitespace();
    let method = parts.next().unwrap_or("").to_string();
    let raw_path = parts.next().unwrap_or("/").to_string();
    let path = raw_path.split('?').next().unwrap_or("/").to_string();

    let mut content_length = 0usize;
    let mut header_bytes = request_line.len();
    loop {
        let mut line = String::new();
        if reader.read_line(&mut line).is_err() {
            return;
        }
        header_bytes += line.len();
        if header_bytes > 8192 {
            write_response(
                &mut stream,
                "431 Request Header Fields Too Large",
                &[],
                "",
            );
            return;
        }
        if line == "\r\n" || line == "\n" || line.is_empty() {
            break;
        }
        if let Some((name, value)) = line.split_once(':') {
            if name.eq_ignore_ascii_case("content-length") {
                content_length = value.trim().parse().unwrap_or(usize::MAX);
            }
        }
    }

    let setup_address = config.setup_address.parse::<IpAddr>().ok();
    let setup_active = shared.lock().expect("state poisoned").setup_active;
    if !setup_active || local_ip != setup_address {
        let host = local_ip
            .map(|ip| ip.to_string())
            .unwrap_or_else(|| "127.0.0.1".into());
        redirect(&mut stream, &format!("http://{host}:{PLAYER_PORT}/"));
        return;
    }

    if method == "GET" {
        if path != "/" {
            redirect(&mut stream, &format!("http://{}/", config.setup_address));
            return;
        }
        let state = shared.lock().expect("state poisoned");
        let page = portal_page(config, &state, setup_ssid);
        drop(state);
        write_response(
            &mut stream,
            "200 OK",
            &[("Content-Type", "text/html; charset=utf-8")],
            &page,
        );
        return;
    }

    if method != "POST" || path != "/connect" {
        write_response(&mut stream, "404 Not Found", &[], "");
        return;
    }
    if content_length > 4096 {
        write_response(&mut stream, "413 Payload Too Large", &[], "");
        return;
    }

    let mut body = vec![0u8; content_length];
    if reader.read_exact(&mut body).is_err() {
        return;
    }
    let form = match std::str::from_utf8(&body)
        .map_err(|_| "invalid UTF-8".to_string())
        .and_then(parse_form)
    {
        Ok(form) => form,
        Err(error) => {
            shared.lock().expect("state poisoned").last_error = error;
            write_response(&mut stream, "400 Bad Request", &[], "");
            return;
        }
    };

    let ssid = form
        .get("ssid")
        .map(|value| value.trim())
        .unwrap_or("")
        .to_string();
    let password = form.get("password").cloned().unwrap_or_default();
    let validation_error = if ssid.is_empty() {
        Some("Оберіть або введіть SSID.")
    } else if ssid.len() > 32 {
        Some("SSID перевищує 32 байти.")
    } else if password.len() > 128 {
        Some("Пароль надто довгий.")
    } else {
        None
    };

    if let Some(error) = validation_error {
        shared.lock().expect("state poisoned").last_error = error.into();
        let state = shared.lock().expect("state poisoned");
        let page = portal_page(config, &state, setup_ssid);
        drop(state);
        write_response(
            &mut stream,
            "400 Bad Request",
            &[("Content-Type", "text/html; charset=utf-8")],
            &page,
        );
        return;
    }

    {
        let mut state = shared.lock().expect("state poisoned");
        if state.connecting {
            write_response(
                &mut stream,
                "409 Conflict",
                &[],
                "Підключення вже виконується.",
            );
            return;
        }
        state.connecting = true;
        state.last_error.clear();
    }

    if tx.send(ControlMessage::Connect { ssid, password }).is_err() {
        shared.lock().expect("state poisoned").connecting = false;
        write_response(&mut stream, "503 Service Unavailable", &[], "");
        return;
    }

    let page = "<!doctype html><html lang=\"uk\"><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>ProAudio Player</title><style>body{font-family:sans-serif;max-width:520px;margin:48px auto;padding:0 20px}</style><h2>Підключення…</h2><p>Точка налаштування тимчасово зникне. Якщо дані правильні, ProAudio Player підключиться до вибраної мережі. Якщо ні — точка налаштування з’явиться знову.</p></html>";
    write_response(
        &mut stream,
        "200 OK",
        &[("Content-Type", "text/html; charset=utf-8")],
        page,
    );
}

fn portal_page(config: &Config, state: &SharedState, setup_ssid: &str) -> String {
    let options = state
        .networks
        .iter()
        .map(|item| {
            format!(
                "<option value=\"{}\">{} — {}% — {}</option>",
                html_escape(&item.ssid),
                html_escape(&item.ssid),
                item.signal,
                html_escape(&item.security)
            )
        })
        .collect::<Vec<_>>()
        .join("\n");
    let error = if state.last_error.is_empty() {
        String::new()
    } else {
        format!(
            "<div class=\"error\">{}</div>",
            html_escape(&state.last_error)
        )
    };
    let disabled = if state.connecting { " disabled" } else { "" };

    format!(
        "<!doctype html><html lang=\"uk\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>ProAudio Player — Wi-Fi</title><style>body{{font-family:system-ui,sans-serif;background:#f5f5f5;margin:0;color:#161616}}main{{max-width:520px;margin:0 auto;padding:32px 20px}}.card{{background:white;border-radius:14px;padding:24px;box-shadow:0 2px 14px #0001}}h1{{font-size:24px;margin-top:0}}label{{display:block;margin:16px 0 6px}}input{{width:100%;box-sizing:border-box;padding:12px;border:1px solid #bbb;border-radius:8px;font-size:16px}}button{{margin-top:20px;width:100%;padding:13px;border:0;border-radius:8px;background:#111;color:#fff;font-size:16px}}small{{color:#666}}.error{{background:#fee;color:#900;padding:10px;border-radius:8px;margin:12px 0}}</style></head><body><main><div class=\"card\"><h1>ProAudio Player</h1><p>Виберіть Wi-Fi мережу та введіть пароль.</p>{error}<form method=\"post\" action=\"/connect\"><label for=\"ssid\">Wi-Fi мережа</label><input id=\"ssid\" name=\"ssid\" list=\"networks\" maxlength=\"32\" required autocomplete=\"off\"><datalist id=\"networks\">{options}</datalist><label for=\"password\">Пароль</label><input id=\"password\" name=\"password\" type=\"password\" autocomplete=\"current-password\"><small>Для відкритої мережі залиште поле порожнім.</small><button type=\"submit\"{disabled}>Підключити</button></form><p><small>Setup AP: {} · {}</small></p></div></main></body></html>",
        html_escape(setup_ssid),
        html_escape(&config.setup_address)
    )
}

fn write_response(stream: &mut TcpStream, status: &str, headers: &[(&str, &str)], body: &str) {
    let _ = write!(
        stream,
        "HTTP/1.1 {status}\r\nContent-Length: {}\r\nCache-Control: no-store\r\nConnection: close\r\n",
        body.len()
    );
    for (name, value) in headers {
        let _ = write!(stream, "{name}: {value}\r\n");
    }
    let _ = write!(stream, "\r\n{body}");
    let _ = stream.flush();
}

fn redirect(stream: &mut TcpStream, location: &str) {
    write_response(stream, "302 Found", &[("Location", location)], "");
}

fn parse_form(body: &str) -> Result<HashMap<String, String>, String> {
    let mut form = HashMap::new();
    for pair in body.split('&') {
        let (key, value) = pair.split_once('=').unwrap_or((pair, ""));
        form.insert(percent_decode(key)?, percent_decode(value)?);
    }
    Ok(form)
}

fn percent_decode(input: &str) -> Result<String, String> {
    let bytes = input.as_bytes();
    let mut output = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        match bytes[index] {
            b'+' => {
                output.push(b' ');
                index += 1;
            }
            b'%' if index + 2 < bytes.len() => {
                let high = hex(bytes[index + 1]).ok_or("invalid percent encoding")?;
                let low = hex(bytes[index + 2]).ok_or("invalid percent encoding")?;
                output.push((high << 4) | low);
                index += 3;
            }
            b'%' => return Err("truncated percent encoding".into()),
            value => {
                output.push(value);
                index += 1;
            }
        }
    }
    String::from_utf8(output).map_err(|_| "form data is not UTF-8".into())
}

fn hex(value: u8) -> Option<u8> {
    match value {
        b'0'..=b'9' => Some(value - b'0'),
        b'a'..=b'f' => Some(value - b'a' + 10),
        b'A'..=b'F' => Some(value - b'A' + 10),
        _ => None,
    }
}

fn html_escape(input: &str) -> String {
    let mut output = String::with_capacity(input.len());
    for character in input.chars() {
        match character {
            '&' => output.push_str("&amp;"),
            '<' => output.push_str("&lt;"),
            '>' => output.push_str("&gt;"),
            '"' => output.push_str("&quot;"),
            '\'' => output.push_str("&#39;"),
            _ => output.push(character),
        }
    }
    output
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_urlencoded_form() {
        let form = parse_form("ssid=Office+WiFi&password=a%2Bb").unwrap();
        assert_eq!(form.get("ssid").unwrap(), "Office WiFi");
        assert_eq!(form.get("password").unwrap(), "a+b");
    }

    #[test]
    fn escapes_portal_html() {
        assert_eq!(html_escape("<A&B>"), "&lt;A&amp;B&gt;");
    }
}
