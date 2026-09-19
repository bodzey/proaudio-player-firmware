use std::io::Read;
use std::process::{ChildStderr, ChildStdout, Command, Stdio};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

pub struct CommandResult {
    pub code: i32,
    pub stdout: String,
    pub stderr: String,
}

impl CommandResult {
    pub fn success(&self) -> bool {
        self.code == 0
    }

    pub fn message(&self) -> String {
        let stderr = self.stderr.trim();
        if !stderr.is_empty() {
            return stderr.to_string();
        }
        self.stdout.trim().to_string()
    }
}

pub fn run(program: &str, args: &[&str], timeout: Duration) -> CommandResult {
    let mut child = match Command::new(program)
        .args(args)
        .env("LC_ALL", "C")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
    {
        Ok(child) => child,
        Err(error) => {
            return CommandResult {
                code: 127,
                stdout: String::new(),
                stderr: error.to_string(),
            };
        }
    };

    let stdout_reader = child.stdout.take().map(read_stdout);
    let stderr_reader = child.stderr.take().map(read_stderr);
    let deadline = Instant::now() + timeout;

    let code = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status.code().unwrap_or(1),
            Ok(None) if Instant::now() < deadline => thread::sleep(Duration::from_millis(50)),
            Ok(None) => {
                let _ = child.kill();
                let _ = child.wait();
                break 124;
            }
            Err(error) => {
                let _ = child.kill();
                let _ = child.wait();
                return CommandResult {
                    code: 125,
                    stdout: join_output(stdout_reader),
                    stderr: append_error(join_output(stderr_reader), &error.to_string()),
                };
            }
        }
    };

    CommandResult {
        code,
        stdout: join_output(stdout_reader),
        stderr: join_output(stderr_reader),
    }
}

fn read_stdout(mut pipe: ChildStdout) -> JoinHandle<String> {
    thread::spawn(move || read_text(&mut pipe))
}

fn read_stderr(mut pipe: ChildStderr) -> JoinHandle<String> {
    thread::spawn(move || read_text(&mut pipe))
}

fn read_text(pipe: &mut impl Read) -> String {
    let mut output = String::new();
    let _ = pipe.read_to_string(&mut output);
    output
}

fn join_output(reader: Option<JoinHandle<String>>) -> String {
    reader
        .and_then(|handle| handle.join().ok())
        .unwrap_or_default()
}

fn append_error(mut stderr: String, error: &str) -> String {
    if !stderr.is_empty() && !stderr.ends_with('\n') {
        stderr.push('\n');
    }
    stderr.push_str(error);
    stderr
}

pub fn split_nmcli_escaped(line: &str) -> Vec<String> {
    let mut fields = Vec::new();
    let mut current = String::new();
    let mut escaped = false;

    for character in line.chars() {
        if escaped {
            current.push(character);
            escaped = false;
        } else if character == '\\' {
            escaped = true;
        } else if character == ':' {
            fields.push(std::mem::take(&mut current));
        } else {
            current.push(character);
        }
    }
    if escaped {
        current.push('\\');
    }
    fields.push(current);
    fields
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_nmcli_escaped_colons() {
        assert_eq!(
            split_nmcli_escaped(r"Office\:5G:88:WPA2"),
            ["Office:5G", "88", "WPA2"]
        );
    }

    #[test]
    fn appends_process_errors_without_losing_stderr() {
        assert_eq!(append_error("warning".into(), "failed"), "warning\nfailed");
        assert_eq!(append_error(String::new(), "failed"), "failed");
    }
}
