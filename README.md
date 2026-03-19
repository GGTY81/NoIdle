# 🚀 NoIdle

> Keep your Linux session alive — the right way.

<p align="center">
  <img src="https://capsule-render.vercel.app/api?type=waving&height=220&color=0:0f172a,50:2563eb,100:2563eb&text=NoIdle&fontColor=ffffff&fontSize=52&fontAlignY=38&desc=Keep%20your%20Linux%20session%20alive&descAlignY=58&animation=fadeIn">
</p>

<div align="center">

<strong>Real input-based inactivity detection for Linux and Wayland.</strong>

<br><br>

<img src="https://img.shields.io/badge/platform-Linux-2ea44f?style=for-the-badge">
<img src="https://img.shields.io/badge/display-Wayland-5c6ac4?style=for-the-badge">
<img src="https://img.shields.io/badge/interface-CLI-111111?style=for-the-badge">
<img src="https://img.shields.io/badge/license-GPLv3-blue?style=for-the-badge">

<br><br>

<img src="https://img.shields.io/github/stars/GGTY81/NoIdle?style=flat-square">
<img src="https://img.shields.io/github/forks/GGTY81/NoIdle?style=flat-square">
<img src="https://img.shields.io/github/issues/GGTY81/NoIdle?style=flat-square">
<img src="https://img.shields.io/github/license/GGTY81/NoIdle?style=flat-square">
<img src="https://img.shields.io/github/last-commit/GGTY81/NoIdle?style=flat-square">

</div>


---

## 🧠 What is NoIdle?

**NoIdle** is a lightweight CLI tool for Linux that prevents session timeout by simulating minimal mouse activity — **only when real inactivity is detected**.

Unlike traditional “mouse jigglers”, NoIdle:

- ✅ Detects *real* mouse inactivity using `libinput`
- ✅ Works properly under **Wayland**
- ✅ Avoids constant fake movement
- ✅ Keeps your session active without interfering with your workflow

---

## 🎯 Why NoIdle?

Most existing tools:

- ❌ Move the mouse constantly
- ❌ Break under Wayland
- ❌ Cause unwanted UI interactions
- ❌ Are unreliable in modern Linux environments

**NoIdle does it right:**

> It only acts when your mouse is truly idle.

---

## ⚙️ How It Works

1. Monitors mouse activity using:

```
libinput debug-events
```

2. Tracks the last real user interaction timestamp

3. When inactivity exceeds the defined interval:

- triggers a minimal movement using:

```
evemu-event
```

4. Resets the inactivity timer

---

## 📦 Requirements

Install dependencies:

```
sudo apt update
sudo apt install evemu-tools libinput-tools
```

### 🔧 Dependency Breakdown

| Package           | Purpose                                  |
|------------------|------------------------------------------|
| libinput-tools   | Detects real mouse activity              |
| evemu-tools      | Simulates precise mouse movement         |

---

## 🚀 Installation

### Option 1 — Quick Install

```
git clone https://github.com/GGTY81/noidle.git
cd noidle
chmod +x install.sh
./install.sh
```

---

### Option 2 — Manual Install

```
chmod +x noidle.sh
sudo cp noidle.sh /usr/local/bin/noidle
```

---

## ▶️ Usage

### Run in foreground (debug mode)

```
noidle run --interval 5 --distance 100 -v
```

---

### Run in background

```
sudo -v
noidle start --interval 60 --distance 1
```

---

### Toggle (recommended)

```
noidle toggle --interval 60 --distance 1
```

---

### Stop

```
noidle stop
```

---

### Status

```
noidle status
```

---

### List mouse devices

```
noidle list-devices
```

---

## 🧪 Example

```
noidle run -i 10 -d 2 -v
```

This will:

- wait 10 seconds of inactivity
- move the mouse by 2 pixels
- print debug logs

---

## ⚠️ Notes

- Requires sudo for:
  - evemu-event
  - libinput debug-events

- To avoid password prompts during execution:

```
sudo -v
```

---

## 🔒 Wayland Compatibility

NoIdle is designed specifically for Wayland environments, where traditional tools fail.

It avoids:

- X11 dependencies
- Fake cursor injection
- Broken hacks

---

## 💡 Use Cases

- Generating long reports
- Preventing session timeout
- Remote support tasks
- Automation workflows
- IT environments

---

## 🧠 Philosophy

> Don't fake activity — detect it.

---

## 👨‍💻 Author

Giovanni Grimaldi Torelly  
GitHub: https://github.com/GGTY81

---

## 📄 License

This project is licensed under the GNU GPL v3 License.

See the LICENSE file for details.
