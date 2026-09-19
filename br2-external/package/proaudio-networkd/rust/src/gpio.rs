use std::io::{BufRead, BufReader};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{mpsc, Arc};
use std::thread;
use std::time::Duration;

use crate::config::Config;
use crate::signals;
use crate::state::ControlMessage;

pub fn start(config: Config, tx: mpsc::Sender<ControlMessage>) {
    thread::spawn(move || {
        let line = config.gpio_line.to_string();
        let hold = Duration::from_secs_f64(config.gpio_hold_seconds.max(0.1));
        let mut child = match Command::new("/usr/bin/gpiomon")
            .args([
                "-c",
                &config.gpio_chip,
                "-b",
                "pull-up",
                "-e",
                "both",
                "-p",
                "50ms",
                "-F",
                "%E",
                &line,
            ])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
        {
            Ok(child) => child,
            Err(error) => {
                eprintln!("WARN GPIO setup button unavailable: {error}");
                return;
            }
        };

        let Some(stdout) = child.stdout.take() else {
            let _ = child.kill();
            return;
        };
        let pressed = Arc::new(AtomicBool::new(false));

        for event in BufReader::new(stdout).lines() {
            if signals::stop_requested() {
                break;
            }
            let Ok(event) = event else {
                break;
            };
            match event.trim() {
                "falling" => {
                    pressed.store(true, Ordering::Relaxed);
                    let pressed = Arc::clone(&pressed);
                    let tx = tx.clone();
                    thread::spawn(move || {
                        thread::sleep(hold);
                        if pressed.load(Ordering::Relaxed) && !signals::stop_requested() {
                            let _ = tx.send(ControlMessage::Setup);
                        }
                    });
                }
                "rising" => pressed.store(false, Ordering::Relaxed),
                _ => {}
            }
        }

        let _ = child.kill();
        let _ = child.wait();
    });
}
