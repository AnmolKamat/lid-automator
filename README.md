# 💻 MacBook Lid Automator (`lid-automator`)

A lightweight, native macOS tool that detects physical MacBook lid angles and triggers automated scripts, notifications, and system actions.

Built with native Swift and Apple Silicon IOKit HID (`AppleSPUHIDDevice`).

---

## ⚡ Quick Install

### Option A: Homebrew Tap (Recommended)
```bash
brew tap AnmolKamat/tap
brew install lid-automator
```

### Option B: One-Liner (curl)
```bash
curl -fsSL https://raw.githubusercontent.com/AnmolKamat/lid-automator/main/install.sh | bash
```

### Option C: Build from Source
```bash
git clone https://github.com/AnmolKamat/lid-automator.git
cd lid-automator
swift build -c release
sudo cp .build/release/lid-automator /usr/local/bin/
```

---

## 🚀 Quick Start

```bash
# 1. Check current lid angle in degrees:
lid-automator status

# 2. Test in the terminal with live visual gauge:
lid-automator run

# 3. Start background daemon (runs 24/7 on login):
lid-automator start

# 4. View real-time logs:
lid-automator logs -f
```

---

## ⚙️ Configuration (`~/.lid-automation/config`)

Default config lives at `~/.lid-automation/config`:

```json
[
  {
    "name": "Lock Screen on Low Angle",
    "angle": "<40",
    "trigger": "enter",
    "notify": true,
    "script": "builtin:lock",
    "enabled": true,
    "rules": {
      "cooldown": 5,
      "rearm": 45
    }
  },
  {
    "name": "Volume 80% & Ping when open past 100°",
    "angle": ">100",
    "trigger": "enter",
    "notify": true,
    "script": "builtin:volume 80",
    "enabled": true,
    "rules": {
      "cooldown": 2,
      "rearm": 95
    }
  },
  {
    "name": "Pause Docker Containers on Lower Lid",
    "angle": "30-50",
    "trigger": "closing",
    "notify": "Docker containers paused",
    "script": "docker ps -q | xargs -r docker pause",
    "enabled": false,
    "rules": {
      "days": ["mon", "tue", "wed", "thu", "fri"],
      "time": "9am-6pm",
      "cooldown": 10
    }
  }
]
```

### Fields:
* **`angle`**: Target angle. E.g. `"<40"`, `">100"`, `"30-60"`, or `40`.
* **`trigger`**: When to trigger:
  * `"enter"` *(default)*: When entering the angle range.
  * `"exit"`: When exiting the angle range.
  * `"closing"`: Only when actively closing the lid into range.
  * `"opening"`: Only when actively opening the lid into range.
  * `"change"`: On both enter and exit.
* **`notify`**: Whether to send macOS Notification Center banner:
  * `true`: Shows standard banner with rule name & angle.
  * `"Custom message"`: Shows custom text.
  * `false`: Silent execution.
* **`script`**: Any shell command or built-in shortcut:
  * `builtin:lock` — Locks screen immediately.
  * `builtin:volume <0-100>` — Sets volume.
  * `builtin:brightness <0-100>` — Sets display brightness.
  * `builtin:beep` / `builtin:sound <Name>` — Plays sound feedback.
  * `node script.js`, `python3 script.py`, `docker ...`
* **`rules`** *(optional filters)*:
  * `time`: Time window string (e.g. `"9am-6pm"` or `"22:00-06:00"`).
  * `days`: Scheduled days (e.g. `["mon", "wed", "fri"]` or `"weekdays"`).
  * `cooldown`: Minimum seconds between triggers (default: 5).
  * `rearm`: Hysteresis angle threshold to re-arm the trigger.

---

## 🛠️ CLI Commands

| Command | Description |
| :--- | :--- |
| `lid-automator list` | Displays table of all automations & active states |
| `lid-automator add` | Interactively or via flags add a new automation |
| `lid-automator test <id>` | Immediately test-runs script and notification banner |
| `lid-automator enable <id>` | Enables a rule |
| `lid-automator disable <id>` | Disables a rule |
| `lid-automator rm <id>` | Removes a rule |
| `lid-automator start` | Registers & starts background daemon via LaunchAgent |
| `lid-automator stop` | Stops background daemon |
| `lid-automator status` | Shows current lid angle, daemon status, and rule count |
| `lid-automator logs [-f]` | Views or follows live execution logs |
| `lid-automator config --choose <path>` | Sets and remembers a custom config path |
| `lid-automator config --reset` | Resets back to `~/.lid-automation/config` |

---

## 🔬 How It Works

Apple Silicon MacBooks route hinge angle data through the Apple SPU (*Sensor Processing Unit*) under the product identifier **`las`** (*Lid Angle Sensor*):

* **Vendor ID:** `0x05AC` (Apple)
* **Product ID:** `0x8104` (Apple SPU)
* **Usage Page:** `0x0020` (Sensor Page)
* **Usage:** `0x008A` (Lid Orientation)

`lid-automator` uses standard `IOKit.hid` APIs (`IOHIDManager`) with hybrid event callbacks + polling watchdog to deliver 0% CPU idle impact and millisecond-level responsiveness.

---

## 📜 License

[MIT](LICENSE) © 2026 Anmol Kamath
