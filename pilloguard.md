---
publishDate: 2026-08-25T00:00:00Z
title: PilloGuard - AI-Powered Closed-Loop Pneumatic Sleep Assistance System
excerpt: PilloGuard is an intelligent sleep-assistance system that combines snoring detection, physiological monitoring, head-position tracking, and closed-loop pneumatic intervention using the MYOSA platform.
image: cover.jpg
tags:
  - sleep-monitoring
  - snoring-detection
  - artificial-intelligence
  - myosa
  - iot
---

> From passive sleep monitoring to intelligent, closed-loop pneumatic intervention.

---

## Acknowledgements

We would like to thank the MYOSA Sensors team for providing the MYOSA platform and sensor development ecosystem that enabled the development and prototyping of PilloGuard.

---

## Overview

Obstructive Sleep Apnea (OSA) and severe snoring are important sleep-related problems that can affect sleep quality and overall well-being.

Traditional sleep-monitoring solutions mainly focus on collecting and displaying information. PilloGuard takes a different approach by combining monitoring with an active pneumatic intervention system.

PilloGuard is built around the MYOSA platform and integrates an ESP32-based hardware layer, physiological monitoring, head-position sensing, AI-based analysis, a mobile sleep-monitoring application, and multiple pneumatic bladder zones.

The system follows a closed-loop concept:

**Sense → Analyze → Decide → Intervene → Measure Feedback → Respond**

The ESP32 collects the required hardware data and controls the pneumatic system. The laptop provides the AI processing layer, while the mobile application provides sleep monitoring, visualization, event logging, and user-facing insights.

### Key Features

- Real-time snoring detection and snore probability.
- SpO₂ and heart-rate monitoring through an external oximeter.
- Head-position and movement tracking using MPU6050.
- Three independently controlled pneumatic bladder zones.
- Three pumps controlled through relays.
- Individual pressure feedback for each pneumatic bladder.
- AI-based analysis of sleep and physiological data.
- Closed-loop pneumatic intervention.
- Local MYOSA sensor monitoring through the OLED display.
- Local SQLite storage and sleep-session history in the mobile application.
- Bluetooth Low Energy hardware integration.

---

## Demo / Examples

### Images

Project images and hardware photographs will be added here.

### Videos

<video controls width="100%">
  <source src="/pilloguard-demo.mp4" type="video/mp4">
</video>

---

## Features (Detailed)

### 1. MYOSA Sensor Platform

PilloGuard uses the MYOSA Mini Kit as part of its embedded hardware platform.

The ESP32-based MYOSA motherboard acts as the main hardware controller and collects sensor information required by the system.

The MYOSA Kit sensors are also used as a local hardware-monitoring layer.

The OLED display provides local feedback from the embedded system.

The **BMP180** is used for local pressure and temperature measurements.

The **APDS9960** provides local environmental information including ambient light, proximity, and gesture sensing.

These local MYOSA measurements are not part of the primary mobile-app telemetry.

---

### 2. Head Position and Movement

The MPU6050 accelerometer and gyroscope are used to monitor head movement and orientation.

The system uses the measured head position to determine the appropriate pneumatic intervention zone.

Depending on the detected position, the controller can select the corresponding bladder zone instead of activating all zones simultaneously.

---

### 3. Pneumatic Bladder System

The pillow contains three pneumatic bladder zones.

Each zone has an independent pump and relay control.

This allows the system to selectively inflate a specific part of the pillow according to the detected head position.

For example, when the user's head moves toward a particular side, the corresponding pneumatic zone can be activated to provide controlled positional support.

The system is designed to keep the intervention targeted rather than continuously inflating the entire pillow.

---

### 4. Pressure Feedback and Safety

Each pneumatic bladder is connected to an individual air-pressure sensor.

The pressure sensors used in the prototype are compact piezo-resistive pressure modules with a nominal measurement range of **0–40 kPa**.

The sensors produce an electrical signal proportional to the applied air pressure and are connected to the pneumatic lines using flexible tubing.

The ESP32 continuously monitors the pressure of each bladder.

This information is used as feedback to determine whether a bladder has reached the required inflation level.

The controller can therefore stop the corresponding pump when the target condition is reached and prevent continued inflation beyond the defined safety limit.

This converts the pneumatic subsystem from a simple open-loop actuator into a **closed-loop pressure-controlled system**.

---

### 5. Snoring Detection

The mobile application uses the device microphone to detect snoring events.

Instead of continuously storing raw audio, the application processes the audio stream using a machine-learning model designed for audio classification.

When a snoring pattern is detected with sufficient confidence, the application records a timestamped snoring event and its associated probability.

This allows snoring activity to be correlated with physiological and movement data.

---

### 6. Physiological Monitoring

The system integrates an external oximeter through Bluetooth Low Energy.

The oximeter provides:

- Blood oxygen saturation (SpO₂)
- Heart rate

These measurements are continuously associated with the sleep-monitoring timeline.

The physiological information is especially important when evaluating whether a snoring event is accompanied by an abnormal oxygen-level change.

---

### 7. AI Decision Layer

The ESP32 acts as the embedded sensing and control layer.

The collected telemetry is transmitted to the laptop, where the AI processing layer analyzes the incoming information.

The AI can combine information such as:

- Snoring detection
- Snore probability
- SpO₂
- Heart rate
- Head position
- Head movement
- Pressure feedback
- Previous intervention state

The objective is to distinguish normal sleep activity from events that may require intervention.

The AI decision is then used to determine whether the pneumatic intervention should remain inactive or whether a specific bladder zone should be activated.

---

### 8. Closed-Loop Intervention

The complete intervention cycle is:

**Snoring / abnormal event detected**

↓

**AI analyzes physiological and positional data**

↓

**Decision engine determines whether intervention is required**

↓

**Select appropriate pneumatic zone**

↓

**Activate corresponding pump**

↓

**Read bladder pressure**

↓

**Stop inflation when the target condition is reached**

↓

**Monitor the user's response**

↓

**Continue monitoring**

This feedback loop is the core concept of PilloGuard.

---

### 9. Sleep Monitoring Application

The mobile application provides the user-facing monitoring interface.

The application is designed around a dark-mode dashboard with real-time monitoring indicators.

During an active sleep session, the application can display information such as:

- Snoring status
- Snore probability
- SpO₂
- Heart rate
- Head movement
- Sensor connection status
- Intervention events

The application is also designed to operate continuously using background execution so that monitoring can continue while the device screen is locked or the application is minimized.

---

### 10. Local Data Storage

Sleep-monitoring information is stored locally using SQLite.

Timestamped events can be correlated across multiple data sources, including:

- Snoring events
- SpO₂
- Heart rate
- Movement
- Head position
- Intervention events

This creates a time-series record of the user's sleep session and provides the foundation for future visualization and sleep analysis.

---

## Usage Instructions

### Hardware

1. Connect the MYOSA ESP32 motherboard.
2. Connect the MYOSA sensors.
3. Connect the MPU6050 for head-position tracking.
4. Connect the three pneumatic bladder pressure sensors.
5. Connect the three pumps through their relay modules.
6. Connect the external oximeter.
7. Power the hardware according to the prototype wiring.
8. Upload the ESP32 firmware.
9. Start the laptop AI processing layer.
10. Start the mobile sleep-monitoring application.

### Sleep Monitoring

Start a sleep session from the mobile application.

The application begins monitoring audio and biometric information while the ESP32 collects the embedded sensor data.

The AI processing layer receives the required telemetry and evaluates the current sleep state.

When an intervention is required, the appropriate pneumatic zone is selected and controlled using the ESP32.

---

## Tech Stack

- **ESP32** — Embedded controller and sensor interface.
- **MYOSA Mini Kit** — Embedded sensing and prototyping platform.
- **MPU6050** — Accelerometer and gyroscope for head movement and orientation.
- **Pressure Sensors (0–40 kPa)** — Individual bladder pressure feedback.
- **Pumps + Relays** — Pneumatic actuation.
- **Oximeter** — SpO₂ and heart-rate monitoring.
- **Flutter / Dart** — Mobile application.
- **TensorFlow Lite / YAMNet-based audio processing** — Snoring detection.
- **Bluetooth Low Energy (BLE)** — Hardware-to-application communication.
- **Flutter Background Service** — Continuous background monitoring.
- **SQLite / sqflite** — Local sleep-session storage.
- **OLED / SSD1306** — Local embedded-system display.

---

## Requirements / Installation

### Embedded System

The ESP32 firmware requires an ESP32-compatible Arduino development environment and the required sensor libraries.

### Mobile Application

The application requires Flutter and its project dependencies.

The main software components include:

```text
Flutter
Dart
flutter_blue_plus
flutter_background_service
sqflite
TensorFlow Lite / audio ML components
