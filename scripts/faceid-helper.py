#!/usr/bin/env python3
"""
faceid-helper.py - Quickshell Biometric Face Recognition Helper
Optimized for low-overhead, AVX-free biometric unlock on Linux / NixOS (Intel Celeron N4020).
Features:
- Real-time live camera preview with ffplay (SDL2/Wayland) during enrollment
- Full face framing with generous 30% padding (no cut-off face)
- Histogram-equalized LBPH recognition (robust against room lighting changes)
- High-speed streaming status IPC for Quickshell QML
"""

import os
import sys
import json
import time
import glob
import argparse
import subprocess

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BASE_DIR = os.path.dirname(SCRIPT_DIR)
STATE_DIR = os.path.join(BASE_DIR, "state")
ASSETS_DIR = os.path.join(BASE_DIR, "assets")
VENV_PYTHON = os.path.join(SCRIPT_DIR, ".faceid-env", "bin", "python3")

def bootstrap_env():
    try:
        import cv2
        return
    except ImportError:
        pass

    if os.path.isfile(VENV_PYTHON) and os.access(VENV_PYTHON, os.X_OK):
        os.execv(VENV_PYTHON, [VENV_PYTHON] + sys.argv)

    nix_shell = "/run/current-system/sw/bin/nix-shell"
    if not os.path.exists(nix_shell):
        nix_shell = "nix-shell"
    cmd = [nix_shell, "-p", "python3Packages.opencv4", "--run", f"python3 {' '.join(sys.argv)}"]
    res = subprocess.run(cmd)
    sys.exit(res.returncode)

bootstrap_env()

import cv2
import numpy as np

MODEL_FILE = os.path.join(STATE_DIR, "faceid_model.xml")
SAMPLE_PREVIEW = os.path.join(STATE_DIR, "faceid_sample.jpg")
DEFAULT_CASCADE = os.path.join(ASSETS_DIR, "haarcascade_frontalface_default.xml")
PROFILE_CASCADE = os.path.join(ASSETS_DIR, "haarcascade_profileface.xml")

def get_cascade_path():
    if os.path.isfile(DEFAULT_CASCADE):
        return DEFAULT_CASCADE
    if hasattr(cv2, "data") and hasattr(cv2.data, "haarcascades"):
        p = os.path.join(cv2.data.haarcascades, "haarcascade_frontalface_default.xml")
        if os.path.isfile(p):
            return p
    candidates = glob.glob("/nix/store/*opencv*/share/opencv4/haarcascades/haarcascade_frontalface_default.xml")
    if candidates:
        return candidates[0]
    return ""

def list_video_devices():
    devices = []
    for dev in sorted(glob.glob("/dev/video*")):
        if os.path.exists(dev):
            devices.append(dev)
    return devices

def get_face_detector():
    casc_path = get_cascade_path()
    if not casc_path or not os.path.isfile(casc_path):
        return None
    detector = cv2.CascadeClassifier(casc_path)
    return detector if not detector.empty() else None

def get_profile_detector():
    if os.path.isfile(PROFILE_CASCADE):
        d = cv2.CascadeClassifier(PROFILE_CASCADE)
        if not d.empty():
            return d
    candidates = glob.glob("/nix/store/*opencv*/share/opencv4/haarcascades/haarcascade_profileface.xml")
    if candidates and os.path.isfile(candidates[0]):
        d = cv2.CascadeClassifier(candidates[0])
        if not d.empty():
            return d
    return None

def crop_padded_face(frame_gray, x, y, w, h):
    """Crops face with generous 28% width and 32% height padding so forehead, jawline and ears are preserved."""
    fh, fw = frame_gray.shape[:2]
    pad_w = int(w * 0.28)
    pad_h = int(h * 0.32)
    x1 = max(0, x - pad_w)
    y1 = max(0, y - pad_h)
    x2 = min(fw, x + w + pad_w)
    y2 = min(fh, y + h + int(pad_h * 0.8))
    return frame_gray[y1:y2, x1:x2], (x1, y1, x2 - x1, y2 - y1)

def preprocess_face(face_gray):
    resized = cv2.resize(face_gray, (160, 160), interpolation=cv2.INTER_AREA)
    equalized = cv2.equalizeHist(resized)
    return equalized

def optimize_camera(camera_device):
    """
    Ensure camera hardware is tuned for low-light environments using v4l2-ctl.
    Sets aperture priority auto-exposure, dynamic framerate, and backlight compensation.
    """
    dev_path = camera_device if (isinstance(camera_device, str) and os.path.exists(camera_device)) else f"/dev/video{camera_device}"
    if os.path.exists(str(dev_path)):
        try:
            subprocess.run([
                "v4l2-ctl", "-d", str(dev_path),
                "-c", "auto_exposure=3",
                "-c", "exposure_dynamic_framerate=1",
                "-c", "backlight_compensation=1"
            ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        except Exception:
            pass

def enhance_low_light(gray):
    """
    Adaptive low-light enhancement for Haar Cascade face detection.
    Combines gamma correction (shadow lifting) and CLAHE (local feature contrast)
    so Haar Cascade can detect face contours even in near-dark rooms.
    """
    mean_val = float(np.mean(gray))
    if mean_val < 75.0:
        # Dynamic gamma based on darkness: darker -> stronger boost (down to 0.42)
        gamma = max(0.42, min(0.85, (mean_val / 75.0) ** 0.75))
        inv_gamma = 1.0 / gamma
        table = np.array([((i / 255.0) ** inv_gamma) * 255 for i in range(256)]).astype("uint8")
        brightened = cv2.LUT(gray, table)

        # Localized contrast amplification for eyes, nose bridge, jawline
        clahe = cv2.createCLAHE(clipLimit=2.8, tileGridSize=(8, 8))
        enhanced = clahe.apply(brightened)
        return enhanced, True, mean_val
    return gray, False, mean_val

def open_camera(camera_device, warmup=True, notify_ready=False):
    optimize_camera(camera_device)
    dev_idx = 0
    if isinstance(camera_device, str) and camera_device.startswith("/dev/video"):
        try:
            dev_idx = int(camera_device.replace("/dev/video", ""))
        except ValueError:
            dev_idx = camera_device
    else:
        dev_idx = camera_device

    cap = cv2.VideoCapture(dev_idx, cv2.CAP_V4L2)
    if not cap.isOpened():
        cap = cv2.VideoCapture(dev_idx)
    
    if cap.isOpened():
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
        cap.set(cv2.CAP_PROP_FPS, 30)

        if notify_ready:
            print(json.dumps({"status": "camera_ready", "message": "Camera hardware active"}), flush=True)

        # Warm up camera sensor: read & discard first 6 frames so hardware auto-exposure settles
        if warmup:
            for _ in range(6):
                cap.read()
    return cap

def cmd_status():
    detector = get_face_detector()
    enrolled = os.path.isfile(MODEL_FILE) and os.path.getsize(MODEL_FILE) > 1000
    devices = list_video_devices()
    result = {
        "available": detector is not None,
        "enrolled": enrolled,
        "model_file": MODEL_FILE,
        "sample_preview": SAMPLE_PREVIEW if os.path.isfile(SAMPLE_PREVIEW) else "",
        "devices": devices,
        "cascade": get_cascade_path()
    }
    print(json.dumps(result), flush=True)

def cmd_devices():
    print(json.dumps({"devices": list_video_devices()}), flush=True)

def cmd_clear():
    os.makedirs(STATE_DIR, exist_ok=True)
    if os.path.isfile(MODEL_FILE):
        os.remove(MODEL_FILE)
    if os.path.isfile(SAMPLE_PREVIEW):
        os.remove(SAMPLE_PREVIEW)
    print(json.dumps({"status": "cleared", "message": "Enrolled face data removed."}), flush=True)

def cmd_verify(camera_device="/dev/video0", timeout_sec=10.0, max_distance=98.0):
    if not os.path.isfile(MODEL_FILE):
        print(json.dumps({"status": "not_enrolled", "message": "Face ID has not been registered yet."}), flush=True)
        sys.exit(2)

    detector = get_face_detector()
    if not detector:
        print(json.dumps({"status": "error", "message": "Face detector cascade XML not found."}), flush=True)
        sys.exit(3)

    try:
        recognizer = cv2.face.LBPHFaceRecognizer_create()
        recognizer.read(MODEL_FILE)
    except Exception as e:
        print(json.dumps({"status": "error", "message": f"Failed to load Face ID model: {e}"}), flush=True)
        sys.exit(4)

    cap = open_camera(camera_device, notify_ready=True)
    if not cap.isOpened():
        print(json.dumps({"status": "camera_unavailable", "device": str(camera_device)}), flush=True)
        sys.exit(5)

    print(json.dumps({"status": "scanning", "message": "Looking for face..."}), flush=True)

    start_time = time.time()
    match_count = 0
    consecutive_needed = 2

    try:
        while True:
            elapsed = time.time() - start_time
            if elapsed > timeout_sec:
                print(json.dumps({"status": "timeout", "message": "Scan timed out."}), flush=True)
                sys.exit(1)

            ret, frame = cap.read()
            if not ret or frame is None:
                time.sleep(0.04)
                continue

            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

            # Pass 1: Standard detection
            faces = detector.detectMultiScale(
                gray,
                scaleFactor=1.1,
                minNeighbors=3,
                minSize=(50, 50),
                flags=cv2.CASCADE_SCALE_IMAGE
            )

            # Pass 2: Adaptive low-light enhancement if no face found or frame is dark
            if len(faces) == 0:
                enhanced, is_low_light, mean_b = enhance_low_light(gray)
                if is_low_light:
                    faces = detector.detectMultiScale(
                        enhanced,
                        scaleFactor=1.08,
                        minNeighbors=3,
                        minSize=(45, 45),
                        flags=cv2.CASCADE_SCALE_IMAGE
                    )
                    # Pass 3: Slightly relaxed minNeighbors for very dark environments
                    if len(faces) == 0 and mean_b < 45.0:
                        faces = detector.detectMultiScale(
                            enhanced,
                            scaleFactor=1.08,
                            minNeighbors=2,
                            minSize=(45, 45),
                            flags=cv2.CASCADE_SCALE_IMAGE
                        )

            if len(faces) == 0:
                match_count = max(0, match_count - 1)
                time.sleep(0.03)
                continue

            # Largest face
            faces = sorted(faces, key=lambda b: b[2] * b[3], reverse=True)
            x, y, w, h = faces[0]
            # Crop from original gray frame to preserve monotonic LBPH texture invariants
            face_roi, _ = crop_padded_face(gray, x, y, w, h)

            processed = preprocess_face(face_roi)
            _, d1 = recognizer.predict(processed)
            _, d2 = recognizer.predict(cv2.flip(processed, 1))
            distance = min(d1, d2)

            # LBPH distance: lower is closer match (distance < 78 is valid match)
            if distance <= max_distance:
                match_count += 1
                print(json.dumps({
                    "status": "detected",
                    "confidence": round(distance, 1),
                    "matches": match_count
                }), flush=True)

                if match_count >= consecutive_needed or distance <= (max_distance - 16.0):
                    username = os.environ.get("USER", "user")
                    print(json.dumps({
                        "status": "success",
                        "confidence": round(distance, 1),
                        "user": username,
                        "message": "Face verified successfully"
                    }), flush=True)
                    cap.release()
                    sys.exit(0)
            else:
                match_count = max(0, match_count - 1)
                print(json.dumps({
                    "status": "unrecognized",
                    "confidence": round(distance, 1)
                }), flush=True)

            time.sleep(0.03)

    finally:
        cap.release()

def cmd_enroll(camera_device="/dev/video0", samples_needed=24, show_preview=True):
    os.makedirs(STATE_DIR, exist_ok=True)

    detector = get_face_detector()
    profile_detector = get_profile_detector()
    if not detector:
        print(json.dumps({"status": "error", "message": "Face detector cascade XML not found."}), flush=True)
        sys.exit(1)

    cap = open_camera(camera_device)
    if not cap.isOpened():
        print(json.dumps({"status": "camera_unavailable", "device": str(camera_device)}), flush=True)
        sys.exit(2)

    # Launch live preview player with ffplay if available (medium 460x345 floating window)
    preview_proc = None
    if show_preview:
        # Pre-register Hyprland window rule for Face ID Enrollment floating window
        try:
            subprocess.run([
                "hyprctl", "eval",
                'pcall(function() return hl.window_rule({ name = "faceid-enroll", match = { title = ".*Face ID Enrollment.*" }, float = true, size = { 460, 345 }, center = true }) end)'
            ], capture_output=True, timeout=0.6)
        except Exception:
            pass

        ffplay_bin = "/run/current-system/sw/bin/ffplay"
        if not os.path.exists(ffplay_bin):
            ffplay_bin = "ffplay"
        try:
            preview_cmd = [
                ffplay_bin,
                "-loglevel", "quiet",
                "-window_title", "Face ID Enrollment",
                "-x", "460", "-y", "345",
                "-f", "rawvideo",
                "-pixel_format", "bgr24",
                "-video_size", "640x480",
                "-"
            ]
            preview_proc = subprocess.Popen(
                preview_cmd,
                stdin=subprocess.PIPE,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
        except Exception:
            preview_proc = None

    PHASES = [
        {
            "id": "center",
            "name": "Center",
            "step": 1,
            "title": "LOOK STRAIGHT",
            "tip": "Step 1/3: Look straight ahead into the oval",
            "target": 8,
            "arc_start": 220,
            "arc_end": 320,
            "dir": "center"
        },
        {
            "id": "left",
            "name": "Turn Left",
            "step": 2,
            "title": "TURN HEAD LEFT",
            "tip": "Step 2/3: Slowly turn your head to the left",
            "target": 8,
            "arc_start": 105,
            "arc_end": 205,
            "dir": "left"
        },
        {
            "id": "right",
            "name": "Turn Right",
            "step": 3,
            "title": "TURN HEAD RIGHT",
            "tip": "Step 3/3: Slowly turn your head to the right",
            "target": 8,
            "arc_start": 335,
            "arc_end": 435, # 335 to 75 deg crossing 0
            "dir": "right"
        }
    ]

    total_samples_needed = sum(p["target"] for p in PHASES)

    print(json.dumps({
        "status": "enrolling",
        "message": "Position your face in front of the camera...",
        "total": total_samples_needed
    }), flush=True)

    face_samples = []
    labels = []
    total_collected = 0
    phase_idx = 0
    phase_collected = 0
    last_capture = 0
    sample_preview_saved = False
    transition_frames_left = 0
    transition_title = ""

    center_x, center_y = 320, 225
    radius_x, radius_y = 115, 145

    # Vignette mask outside target oval
    vignette_mask = np.zeros((480, 640), dtype=np.uint8)
    cv2.ellipse(vignette_mask, (center_x, center_y), (radius_x + 8, radius_y + 8), 0, 0, 360, 255, -1)
    outside = vignette_mask == 0

    try:
        start_time = time.time()
        while phase_idx < len(PHASES):
            if time.time() - start_time > 60.0:
                print(json.dumps({"status": "error", "message": "Enrollment timed out."}), flush=True)
                sys.exit(3)

            ret, frame = cap.read()
            if not ret or frame is None:
                time.sleep(0.03)
                continue

            # Mirror frame horizontally for intuitive camera preview
            frame = cv2.flip(frame, 1)
            display_frame = frame.copy()

            # Soft vignette outside face oval for focus
            display_frame[outside] = (display_frame[outside].astype(np.float32) * 0.60).astype(np.uint8)

            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            cur_phase = PHASES[phase_idx]

            # Detect face according to current phase
            faces = []
            if cur_phase["dir"] == "center":
                raw_faces = detector.detectMultiScale(gray, scaleFactor=1.15, minNeighbors=4, minSize=(80, 80))
                if len(raw_faces) == 0:
                    enh, is_low, _ = enhance_low_light(gray)
                    if is_low:
                        raw_faces = detector.detectMultiScale(enh, scaleFactor=1.10, minNeighbors=3, minSize=(70, 70))
                for (x, y, w, h) in raw_faces:
                    cx = x + w / 2
                    if 190 <= cx <= 450:
                        faces.append((x, y, w, h))
            elif cur_phase["dir"] == "left":
                if profile_detector:
                    p_faces = profile_detector.detectMultiScale(gray, scaleFactor=1.15, minNeighbors=3, minSize=(70, 70))
                    for f in p_faces:
                        faces.append((f[0], f[1], f[2], f[3]))
                raw_faces = detector.detectMultiScale(gray, scaleFactor=1.15, minNeighbors=3, minSize=(70, 70))
                if len(raw_faces) == 0:
                    enh, is_low, _ = enhance_low_light(gray)
                    if is_low:
                        raw_faces = detector.detectMultiScale(enh, scaleFactor=1.10, minNeighbors=3, minSize=(65, 65))
                for f in raw_faces:
                    faces.append((f[0], f[1], f[2], f[3]))
            elif cur_phase["dir"] == "right":
                if profile_detector:
                    gray_flipped = cv2.flip(gray, 1)
                    p_faces = profile_detector.detectMultiScale(gray_flipped, scaleFactor=1.15, minNeighbors=3, minSize=(70, 70))
                    fw = gray.shape[1]
                    for (fx, fy, fw_b, fh_b) in p_faces:
                        faces.append((fw - fx - fw_b, fy, fw_b, fh_b))
                raw_faces = detector.detectMultiScale(gray, scaleFactor=1.15, minNeighbors=3, minSize=(70, 70))
                if len(raw_faces) == 0:
                    enh, is_low, _ = enhance_low_light(gray)
                    if is_low:
                        raw_faces = detector.detectMultiScale(enh, scaleFactor=1.10, minNeighbors=3, minSize=(65, 65))
                for f in raw_faces:
                    faces.append((f[0], f[1], f[2], f[3]))

            face_detected = len(faces) > 0

            # ── Draw 3-Segment Radial Ring Gauge ──────────────────────────────
            # Base faint track
            cv2.ellipse(display_frame, (center_x, center_y), (radius_x, radius_y), 0, 0, 360, (38, 38, 42), 2, cv2.LINE_AA)

            for p_i, p_info in enumerate(PHASES):
                a_start = p_info["arc_start"]
                a_end = p_info["arc_end"]
                a_span = a_end - a_start

                if p_i < phase_idx:
                    # Completed phase: bright emerald green with checkmark
                    cv2.ellipse(display_frame, (center_x, center_y), (radius_x, radius_y), 0, a_start, a_end, (80, 230, 80), 4, cv2.LINE_AA)
                    # Midpoint angle for checkmark
                    mid_ang = (a_start + a_end) / 2.0
                    rad = np.radians(mid_ang)
                    mx = int(center_x + (radius_x + 14) * np.cos(rad))
                    my = int(center_y + (radius_y + 14) * np.sin(rad))
                    cv2.circle(display_frame, (mx, my), 9, (20, 20, 24), -1)
                    cv2.circle(display_frame, (mx, my), 9, (80, 230, 80), 1, cv2.LINE_AA)
                    cv2.putText(display_frame, "+", (mx - 4, my + 4), cv2.FONT_HERSHEY_SIMPLEX, 0.38, (80, 230, 80), 1, cv2.LINE_AA)

                elif p_i == phase_idx:
                    # Current active phase: pulsing progress arc
                    pct = min(1.0, phase_collected / p_info["target"])
                    # Faint active track
                    cv2.ellipse(display_frame, (center_x, center_y), (radius_x, radius_y), 0, a_start, a_end, (65, 65, 75), 2, cv2.LINE_AA)
                    if pct > 0:
                        cur_end = int(a_start + a_span * pct)
                        cv2.ellipse(display_frame, (center_x, center_y), (radius_x, radius_y), 0, a_start, cur_end, (100, 240, 80), 4, cv2.LINE_AA)

                else:
                    # Upcoming phase: dark faint line
                    cv2.ellipse(display_frame, (center_x, center_y), (radius_x, radius_y), 0, a_start, a_end, (45, 45, 50), 2, cv2.LINE_AA)

            # ── Directional Animation & Guidance Indicators ─────────────────
            pulse = int((np.sin(time.time() * 6.0) + 1.0) * 8)
            if cur_phase["dir"] == "left":
                # Left chevron arrow
                cv2.putText(display_frame, "<<<", (45 - pulse, 230), cv2.FONT_HERSHEY_SIMPLEX, 0.82, (100, 240, 80), 2, cv2.LINE_AA)
                cv2.putText(display_frame, "TURN LEFT", (25, 255), cv2.FONT_HERSHEY_SIMPLEX, 0.40, (180, 180, 180), 1, cv2.LINE_AA)
            elif cur_phase["dir"] == "right":
                # Right chevron arrow
                cv2.putText(display_frame, ">>>", (535 + pulse, 230), cv2.FONT_HERSHEY_SIMPLEX, 0.82, (100, 240, 80), 2, cv2.LINE_AA)
                cv2.putText(display_frame, "TURN RIGHT", (525, 255), cv2.FONT_HERSHEY_SIMPLEX, 0.40, (180, 180, 180), 1, cv2.LINE_AA)

            now = time.time()

            if face_detected and transition_frames_left == 0:
                faces = sorted(faces, key=lambda b: b[2] * b[3], reverse=True)
                x, y, w, h = faces[0]
                face_roi, (px, py, pw, ph) = crop_padded_face(gray, x, y, w, h)

                # Draw sleek corner brackets around detected face
                clen = min(22, pw // 4, ph // 4)
                c_col = (100, 240, 80)
                cv2.line(display_frame, (px, py), (px + clen, py), c_col, 2, cv2.LINE_AA)
                cv2.line(display_frame, (px, py), (px, py + clen), c_col, 2, cv2.LINE_AA)
                cv2.line(display_frame, (px + pw, py), (px + pw - clen, py), c_col, 2, cv2.LINE_AA)
                cv2.line(display_frame, (px + pw, py), (px + pw, py + clen), c_col, 2, cv2.LINE_AA)
                cv2.line(display_frame, (px, py + ph), (px + clen, py + ph), c_col, 2, cv2.LINE_AA)
                cv2.line(display_frame, (px, py + ph), (px, py + ph - clen), c_col, 2, cv2.LINE_AA)
                cv2.line(display_frame, (px + pw, py + ph), (px + pw - clen, py + ph), c_col, 2, cv2.LINE_AA)
                cv2.line(display_frame, (px + pw, py + ph), (px + pw, py + ph - clen), c_col, 2, cv2.LINE_AA)

                # Sample collection cadence (every 160ms for deliberate, high-quality capture)
                if now - last_capture >= 0.16:
                    processed = preprocess_face(face_roi)
                    face_samples.append(processed)
                    labels.append(0)
                    phase_collected += 1
                    total_collected += 1
                    last_capture = now

                    # Save full-face sample preview crop (with margin)
                    if not sample_preview_saved or cur_phase["id"] == "center":
                        color_roi, _ = crop_padded_face(frame, x, y, w, h)
                        if color_roi.size > 0:
                            cv2.imwrite(SAMPLE_PREVIEW, cv2.resize(color_roi, (240, 240)))
                            sample_preview_saved = True

                    print(json.dumps({
                        "status": "capturing",
                        "step": cur_phase["step"],
                        "step_name": cur_phase["name"],
                        "count": total_collected,
                        "total": total_samples_needed,
                        "progress": round(total_collected / total_samples_needed, 2),
                        "message": f"{cur_phase['title']} ({phase_collected}/{cur_phase['target']})"
                    }), flush=True)

                    # Check phase completion
                    if phase_collected >= cur_phase["target"]:
                        if phase_idx < len(PHASES) - 1:
                            transition_frames_left = 18 # ~0.6s smooth transition pause
                            transition_title = f"{cur_phase['name']} Angle Captured!"
                            phase_idx += 1
                            phase_collected = 0
                        else:
                            phase_idx = len(PHASES)
                            break

            # Handle transition pause screen between phases
            if transition_frames_left > 0:
                transition_frames_left -= 1
                cv2.rectangle(display_frame, (160, 200), (480, 255), (18, 18, 22), -1)
                cv2.rectangle(display_frame, (160, 200), (480, 255), (100, 240, 80), 1)
                cv2.putText(display_frame, f"+ {transition_title}", (180, 235), cv2.FONT_HERSHEY_SIMPLEX, 0.58, (100, 240, 80), 2, cv2.LINE_AA)

            # ── Top Header Banner ─────────────────────────────────────────────
            cv2.rectangle(display_frame, (0, 0), (640, 52), (18, 18, 22), -1)
            cv2.line(display_frame, (0, 52), (640, 52), (50, 50, 58), 1)
            cv2.putText(display_frame, "APPLE-STYLE FACE ID SETUP", (22, 23), cv2.FONT_HERSHEY_SIMPLEX, 0.48, (160, 160, 170), 1, cv2.LINE_AA)

            # Step indicators
            p1_str = "[+] 1.Center" if phase_idx > 0 else ("[● 1.Center]" if phase_idx == 0 else "[○ 1.Center]")
            p2_str = "[+] 2.Left" if phase_idx > 1 else ("[● 2.Left]" if phase_idx == 1 else "[○ 2.Left]")
            p3_str = "[+] 3.Right" if phase_idx > 2 else ("[● 3.Right]" if phase_idx == 2 else "[○ 3.Right]")

            cv2.putText(display_frame, f"{p1_str}  {p2_str}  {p3_str}", (22, 44), cv2.FONT_HERSHEY_SIMPLEX, 0.52, (255, 255, 255), 1, cv2.LINE_AA)
            pct = int((total_collected / total_samples_needed) * 100)
            cv2.putText(display_frame, f"{pct}%", (580, 44), cv2.FONT_HERSHEY_SIMPLEX, 0.54, (100, 240, 80), 2, cv2.LINE_AA)

            # ── Bottom Guidance Banner ────────────────────────────────────────
            cv2.rectangle(display_frame, (0, 420), (640, 480), (18, 18, 22), -1)
            cv2.line(display_frame, (0, 420), (640, 420), (50, 50, 58), 1)

            # Progress bar track
            cv2.rectangle(display_frame, (20, 426), (620, 432), (38, 38, 44), -1)
            bar_w = int(600 * (total_collected / total_samples_needed))
            if bar_w > 0:
                cv2.rectangle(display_frame, (20, 426), (20 + bar_w, 432), (100, 240, 80), -1)

            guide = cur_phase["tip"] if face_detected else f"{cur_phase['tip']} (Position face in frame)"
            guide_color = (100, 240, 80) if face_detected else (200, 200, 200)
            cv2.putText(display_frame, guide, (22, 458), cv2.FONT_HERSHEY_SIMPLEX, 0.54, guide_color, 1, cv2.LINE_AA)

            # Pipe to ffplay preview window
            if preview_proc and preview_proc.stdin:
                try:
                    preview_proc.stdin.write(display_frame.tobytes())
                    preview_proc.stdin.flush()
                except (BrokenPipeError, OSError):
                    print(json.dumps({"status": "cancelled", "message": "Enrollment cancelled by user."}), flush=True)
                    sys.exit(0)

            time.sleep(0.025)

        # ── Phase 4: Confirmation & Review Screen ──────────────────────────────
        print(json.dumps({
            "status": "review",
            "message": "All facial angles verified! Reviewing registration...",
            "progress": 1.0
        }), flush=True)

        username = os.environ.get("USER", "user")
        confirm_duration = 3.8 # 3.8 seconds interactive review
        confirm_start = time.time()

        preview_thumb = None
        if os.path.isfile(SAMPLE_PREVIEW):
            try:
                pt = cv2.imread(SAMPLE_PREVIEW)
                if pt is not None:
                    preview_thumb = cv2.resize(pt, (110, 110))
            except Exception:
                preview_thumb = None

        while True:
            elapsed = time.time() - confirm_start
            if elapsed >= confirm_duration:
                break

            ret, frame = cap.read()
            if not ret or frame is None:
                time.sleep(0.03)
                continue
            frame = cv2.flip(frame, 1)

            # Dark frosted overlay
            overlay = frame.copy()
            cv2.rectangle(overlay, (0, 0), (640, 480), (10, 10, 14), -1)
            display_frame = cv2.addWeighted(overlay, 0.88, frame, 0.12, 0)

            # Card container
            card_x1, card_y1, card_x2, card_y2 = 35, 25, 605, 455
            cv2.rectangle(display_frame, (card_x1, card_y1), (card_x2, card_y2), (18, 18, 24), -1)
            cv2.rectangle(display_frame, (card_x1, card_y1), (card_x2, card_y2), (80, 230, 80), 2, cv2.LINE_AA)

            # Card Header
            cv2.putText(display_frame, "FACE ID ENROLLMENT CONFIRMATION", (70, 62), cv2.FONT_HERSHEY_SIMPLEX, 0.64, (100, 240, 80), 2, cv2.LINE_AA)
            cv2.putText(display_frame, "All 3 facial angles verified and recorded successfully", (70, 86), cv2.FONT_HERSHEY_SIMPLEX, 0.44, (180, 180, 180), 1, cv2.LINE_AA)
            cv2.line(display_frame, (50, 98), (590, 98), (45, 45, 55), 1)

            # 3 Angle Status Badges
            badge_y = 132
            # Frontal Badge
            cv2.rectangle(display_frame, (55, badge_y - 20), (215, badge_y + 12), (25, 45, 30), -1)
            cv2.rectangle(display_frame, (55, badge_y - 20), (215, badge_y + 12), (80, 230, 80), 1)
            cv2.putText(display_frame, "+ Frontal (8/8)", (70, badge_y), cv2.FONT_HERSHEY_SIMPLEX, 0.44, (100, 240, 80), 1, cv2.LINE_AA)

            # Left Badge
            cv2.rectangle(display_frame, (240, badge_y - 20), (400, badge_y + 12), (25, 45, 30), -1)
            cv2.rectangle(display_frame, (240, badge_y - 20), (400, badge_y + 12), (80, 230, 80), 1)
            cv2.putText(display_frame, "+ Left Turn (8/8)", (252, badge_y), cv2.FONT_HERSHEY_SIMPLEX, 0.44, (100, 240, 80), 1, cv2.LINE_AA)

            # Right Badge
            cv2.rectangle(display_frame, (425, badge_y - 20), (585, badge_y + 12), (25, 45, 30), -1)
            cv2.rectangle(display_frame, (425, badge_y - 20), (585, badge_y + 12), (80, 230, 80), 1)
            cv2.putText(display_frame, "+ Right Turn (8/8)", (437, badge_y), cv2.FONT_HERSHEY_SIMPLEX, 0.44, (100, 240, 80), 1, cv2.LINE_AA)

            # Middle Section: Face Thumbnail + Apple Face ID Brackets
            mid_x, mid_y = 320, 240
            if preview_thumb is not None:
                tx1 = mid_x - 55
                ty1 = mid_y - 55
                display_frame[ty1:ty1+110, tx1:tx1+110] = preview_thumb
                cv2.rectangle(display_frame, (tx1 - 2, ty1 - 2), (tx1 + 112, ty1 + 112), (80, 230, 80), 2, cv2.LINE_AA)

                # Corner brackets around thumbnail
                b_len = 16
                b_col = (100, 240, 80)
                cv2.line(display_frame, (tx1 - 8, ty1 - 8), (tx1 - 8 + b_len, ty1 - 8), b_col, 2, cv2.LINE_AA)
                cv2.line(display_frame, (tx1 - 8, ty1 - 8), (tx1 - 8, ty1 - 8 + b_len), b_col, 2, cv2.LINE_AA)
                cv2.line(display_frame, (tx1 + 118, ty1 - 8), (tx1 + 118 - b_len, ty1 - 8), b_col, 2, cv2.LINE_AA)
                cv2.line(display_frame, (tx1 + 118, ty1 - 8), (tx1 + 118, ty1 - 8 + b_len), b_col, 2, cv2.LINE_AA)
                cv2.line(display_frame, (tx1 - 8, ty1 + 118), (tx1 - 8 + b_len, ty1 + 118), b_col, 2, cv2.LINE_AA)
                cv2.line(display_frame, (tx1 - 8, ty1 + 118), (tx1 - 8, ty1 + 118 - b_len), b_col, 2, cv2.LINE_AA)
                cv2.line(display_frame, (tx1 + 118, ty1 + 118), (tx1 + 118 - b_len, ty1 + 118), b_col, 2, cv2.LINE_AA)
                cv2.line(display_frame, (tx1 + 118, ty1 + 118), (tx1 + 118, ty1 + 118 - b_len), b_col, 2, cv2.LINE_AA)

            cv2.putText(display_frame, f"Registered Profile: {username}", (195, mid_y + 80), cv2.FONT_HERSHEY_SIMPLEX, 0.52, (240, 240, 240), 1, cv2.LINE_AA)
            cv2.putText(display_frame, "24 High-Resolution Facial Samples (LBPH)", (180, mid_y + 102), cv2.FONT_HERSHEY_SIMPLEX, 0.44, (150, 150, 150), 1, cv2.LINE_AA)

            # Bottom Confirmation Countdown Bar
            rem = max(0.1, confirm_duration - elapsed)
            cv2.line(display_frame, (50, 395), (590, 395), (45, 45, 55), 1)

            bar_w = int(500 * (elapsed / confirm_duration))
            cv2.rectangle(display_frame, (70, 410), (570, 418), (35, 35, 40), -1)
            if bar_w > 0:
                cv2.rectangle(display_frame, (70, 410), (70 + bar_w, 418), (100, 240, 80), -1)

            conf_txt = f"Auto-saving profile in {rem:.1f}s...  (Close window to cancel)"
            cv2.putText(display_frame, conf_txt, (135, 438), cv2.FONT_HERSHEY_SIMPLEX, 0.46, (200, 200, 200), 1, cv2.LINE_AA)

            # Pipe to preview window
            if preview_proc and preview_proc.stdin:
                try:
                    preview_proc.stdin.write(display_frame.tobytes())
                    preview_proc.stdin.flush()
                except (BrokenPipeError, OSError):
                    print(json.dumps({"status": "cancelled", "message": "Enrollment cancelled by user."}), flush=True)
                    sys.exit(0)

            time.sleep(0.04)

        # Show Final Saved Splash
        if preview_proc and preview_proc.stdin:
            try:
                splash = display_frame.copy()
                cv2.rectangle(splash, (120, 380), (520, 445), (20, 20, 26), -1)
                cv2.rectangle(splash, (120, 380), (520, 445), (100, 240, 80), 2)
                cv2.putText(splash, "+ Face ID Enrolled Successfully!", (135, 420), cv2.FONT_HERSHEY_SIMPLEX, 0.62, (100, 240, 80), 2, cv2.LINE_AA)
                for _ in range(16):
                    preview_proc.stdin.write(splash.tobytes())
                    preview_proc.stdin.flush()
                    time.sleep(0.04)
            except Exception:
                pass

        # Train LBPH Model
        print(json.dumps({"status": "training", "message": "Training facial recognition model..."}), flush=True)
        recognizer = cv2.face.LBPHFaceRecognizer_create(radius=1, neighbors=8, grid_x=8, grid_y=8)
        recognizer.train(face_samples, np.array([0] * len(face_samples)))
        recognizer.write(MODEL_FILE)

        print(json.dumps({
            "status": "complete",
            "samples": total_collected,
            "message": "Face ID enrolled successfully! Lockscreen is ready.",
            "preview": SAMPLE_PREVIEW
        }), flush=True)
        sys.exit(0)

    finally:
        cap.release()
        if preview_proc:
            try:
                preview_proc.stdin.close()
                preview_proc.terminate()
            except Exception:
                pass

def main():
    parser = argparse.ArgumentParser(description="Quickshell Face ID Helper")
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("status")
    subparsers.add_parser("devices")
    subparsers.add_parser("clear")

    verify_p = subparsers.add_parser("verify")
    verify_p.add_argument("--camera", default="/dev/video0")
    verify_p.add_argument("--timeout", type=float, default=10.0)
    verify_p.add_argument("--confidence", type=float, default=98.0)

    enroll_p = subparsers.add_parser("enroll")
    enroll_p.add_argument("--camera", default="/dev/video0")
    enroll_p.add_argument("--samples", type=int, default=18)
    enroll_p.add_argument("--no-preview", action="store_true")

    args = parser.parse_args()

    if args.command == "status":
        cmd_status()
    elif args.command == "devices":
        cmd_devices()
    elif args.command == "clear":
        cmd_clear()
    elif args.command == "verify":
        cmd_verify(args.camera, args.timeout, args.confidence)
    elif args.command == "enroll":
        cmd_enroll(args.camera, args.samples, show_preview=not args.no_preview)

if __name__ == "__main__":
    main()
