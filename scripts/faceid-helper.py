#!/usr/bin/env python3
"""
faceid-helper.py - Quickshell Biometric Face Recognition Helper
Powered by OpenCV YuNet (Face Detection) + SFace (Face Recognition) via ONNX.
Zero reliance on cv2.face (contrib) for rock-solid stability across NixOS and Arch.
"""

import os
import sys
import json
import time
import glob
import argparse
import subprocess
import shutil

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BASE_DIR = os.path.dirname(SCRIPT_DIR)
ASSETS_DIR = os.path.join(BASE_DIR, "assets")


def xdg_dir(env_name, fallback_parts):
    base = os.environ.get(env_name)
    if not base:
        base = os.path.join(os.path.expanduser("~"), *fallback_parts)
    return base


STATE_DIR = os.path.join(xdg_dir("XDG_STATE_HOME", [".local", "state"]), "quickshell", "faceid")
LEGACY_STATE_DIR = os.path.join(BASE_DIR, "state")

def find_working_python():
    candidates = [
        os.environ.get("FACEID_PYTHON"),
        os.path.join(STATE_DIR, "python-env", "bin", "python"),
        os.path.join(STATE_DIR, "python-env", "bin", "python3"),
        os.path.expanduser("~/.local/state/quickshell/faceid/python-env/bin/python"),
    ]
    # Jika di NixOS, cari environment python dengan opencv di /nix/store
    if os.path.exists("/nix/store"):
        store_candidates = glob.glob("/nix/store/*python3*-env/bin/python")
        candidates.extend(reversed(sorted(store_candidates)))

    current_exe = os.path.realpath(sys.executable)
    for cand in candidates:
        if cand and os.path.isfile(cand) and os.access(cand, os.X_OK):
            cand_real = os.path.realpath(cand)
            if cand_real != current_exe:
                return cand
    return None


def ensure_cv2():
    global cv2, np
    needs_reexec = False
    try:
        import cv2
        import numpy as np
        if not hasattr(cv2, "FaceDetectorYN") or not hasattr(cv2, "FaceRecognizerSF"):
            needs_reexec = True
    except ImportError:
        needs_reexec = True

    if needs_reexec:
        alt_py = find_working_python()
        if alt_py and not os.environ.get("_FACEID_REEXEC"):
            os.environ["_FACEID_REEXEC"] = "1"
            os.environ["FACEID_PYTHON"] = alt_py
            try:
                os.execv(alt_py, [alt_py] + sys.argv)
            except Exception:
                pass

        print(json.dumps({
            "status": "error",
            "message": "OpenCV / NumPy belum terinstall atau versi < 4.5.4 tanpa FaceDetectorYN & FaceRecognizerSF."
        }), flush=True)
        sys.exit(1)


ensure_cv2()

# Model ONNX path
YUNET_MODEL = os.path.join(ASSETS_DIR, "face_detection_yunet_2023mar.onnx")
SFACE_MODEL = os.path.join(ASSETS_DIR, "face_recognition_sface_2021dec.onnx")

# File penyimpanan biometrik
EMBEDDINGS_FILE = os.path.join(STATE_DIR, "faceid_embeddings.npy")
LEGACY_MODEL_FILE = os.path.join(STATE_DIR, "faceid_model.xml")
SAMPLE_PREVIEW = os.path.join(STATE_DIR, "faceid_sample.jpg")

# Cosine similarity default rekomendasi OpenCV SFace
DEFAULT_COSINE_THRESHOLD = 0.363


def list_video_devices():
    devices = []
    for dev in sorted(glob.glob("/dev/video*")):
        if os.path.exists(dev):
            devices.append(dev)
    return devices


def ensure_state_dir():
    os.makedirs(STATE_DIR, exist_ok=True)
    if os.path.isdir(LEGACY_STATE_DIR):
        for name in ("faceid_embeddings.npy", "faceid_sample.jpg"):
            legacy_file = os.path.join(LEGACY_STATE_DIR, name)
            new_file = os.path.join(STATE_DIR, name)
            if os.path.isfile(legacy_file) and not os.path.isfile(new_file):
                try:
                    shutil.copy2(legacy_file, new_file)
                except Exception:
                    pass


def resolve_camera_device(camera_device):
    if isinstance(camera_device, str):
        if os.path.exists(camera_device):
            return camera_device
        if camera_device.isdigit():
            candidate = f"/dev/video{camera_device}"
            if os.path.exists(candidate):
                return candidate
    elif isinstance(camera_device, int):
        candidate = f"/dev/video{camera_device}"
        if os.path.exists(candidate):
            return candidate

    devices = list_video_devices()
    if devices:
        return devices[0]
    return camera_device


def optimize_camera(camera_device):
    dev_path = resolve_camera_device(camera_device)
    if isinstance(dev_path, str) and os.path.exists(dev_path):
        try:
            subprocess.run([
                "v4l2-ctl", "-d", str(dev_path),
                "-c", "auto_exposure=3",
                "-c", "exposure_dynamic_framerate=1",
                "-c", "backlight_compensation=1"
            ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        except Exception:
            pass


def open_camera(camera_device, warmup=True, notify_ready=False):
    optimize_camera(camera_device)
    dev_path = resolve_camera_device(camera_device)
    dev_idx = dev_path
    if isinstance(dev_path, str) and dev_path.startswith("/dev/video"):
        try:
            dev_idx = int(dev_path.replace("/dev/video", ""))
        except ValueError:
            dev_idx = dev_path

    cap = cv2.VideoCapture(dev_idx, cv2.CAP_V4L2)
    if not cap.isOpened():
        cap = cv2.VideoCapture(dev_idx)

    if cap.isOpened():
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
        cap.set(cv2.CAP_PROP_FPS, 30)

        if notify_ready:
            print(json.dumps({"status": "camera_ready", "message": "Camera hardware active"}), flush=True)

        if warmup:
            for _ in range(6):
                cap.read()
    return cap


def get_face_detector(input_size=(640, 480), score_threshold=0.7, nms_threshold=0.3):
    if not os.path.isfile(YUNET_MODEL):
        return None
    try:
        detector = cv2.FaceDetectorYN.create(
            model=YUNET_MODEL,
            config="",
            input_size=input_size,
            score_threshold=score_threshold,
            nms_threshold=nms_threshold,
            top_k=5000
        )
        return detector
    except Exception:
        return None


def get_face_recognizer():
    if not os.path.isfile(SFACE_MODEL):
        return None
    try:
        recognizer = cv2.FaceRecognizerSF.create(
            model=SFACE_MODEL,
            config=""
        )
        return recognizer
    except Exception:
        return None


def enhance_low_light(bgr_img):
    gray = cv2.cvtColor(bgr_img, cv2.COLOR_BGR2GRAY)
    mean_val = float(np.mean(gray))
    if mean_val < 70.0:
        gamma = max(0.45, min(0.85, (mean_val / 70.0) ** 0.75))
        inv_gamma = 1.0 / gamma
        table = np.array([((i / 255.0) ** inv_gamma) * 255 for i in range(256)]).astype("uint8")
        brightened = cv2.LUT(bgr_img, table)

        # CLAHE on luminance in LAB color space
        lab = cv2.cvtColor(brightened, cv2.COLOR_BGR2LAB)
        l, a, b = cv2.split(lab)
        clahe = cv2.createCLAHE(clipLimit=2.5, tileGridSize=(8, 8))
        cl = clahe.apply(l)
        limg = cv2.merge((cl, a, b))
        enhanced = cv2.cvtColor(limg, cv2.COLOR_LAB2BGR)
        return enhanced, True, mean_val
    return bgr_img, False, mean_val


def parse_confidence_threshold(confidence_arg):
    try:
        val = float(confidence_arg)
    except (TypeError, ValueError):
        return DEFAULT_COSINE_THRESHOLD

    # Jika nilai >= 80.0, itu adalah legacy threshold LBPH (98.0) dari config lama
    if val >= 80.0:
        return DEFAULT_COSINE_THRESHOLD
    # Jika 0.0 < val <= 1.0, langsung gunakan sebagai threshold Cosine similarity
    if 0.0 < val <= 1.0:
        return val
    # Jika 1.0 < val < 80.0, asumsikan persentase (misal 36.3 -> 0.363)
    if 1.0 < val < 80.0:
        return val / 100.0
    return DEFAULT_COSINE_THRESHOLD


def is_enrolled():
    if not os.path.isfile(EMBEDDINGS_FILE):
        return False
    try:
        data = np.load(EMBEDDINGS_FILE)
        return data is not None and len(data) > 0
    except Exception:
        return False


# ── CLI Commands ─────────────────────────────────────────────────────────────

def cmd_status():
    ensure_state_dir()
    detector = get_face_detector()
    recognizer = get_face_recognizer()
    enrolled = is_enrolled()
    devices = list_video_devices()

    legacy_model_found = os.path.isfile(LEGACY_MODEL_FILE) and not enrolled

    result = {
        # Sesuai kontrak QML: face_module_available menandakan engine recognizer siap
        "face_module_available": recognizer is not None,
        "detector_available": detector is not None,
        "enrolled": enrolled,
        "legacy_model_detected": legacy_model_found,
        "model_file": EMBEDDINGS_FILE,
        "sample_preview": SAMPLE_PREVIEW if os.path.isfile(SAMPLE_PREVIEW) else "",
        "devices": devices,
        "ready_to_enroll": (recognizer is not None) and (detector is not None) and len(devices) > 0,
    }
    print(json.dumps(result), flush=True)


def cmd_devices():
    print(json.dumps({"devices": list_video_devices()}), flush=True)


def cmd_clear():
    ensure_state_dir()
    for path in (EMBEDDINGS_FILE, LEGACY_MODEL_FILE, SAMPLE_PREVIEW):
        if os.path.isfile(path):
            try:
                os.remove(path)
            except Exception:
                pass
    for name in ("faceid_embeddings.npy", "faceid_model.xml", "faceid_sample.jpg"):
        legacy_file = os.path.join(LEGACY_STATE_DIR, name)
        if os.path.isfile(legacy_file):
            try:
                os.remove(legacy_file)
            except Exception:
                pass
    print(json.dumps({"status": "cleared", "message": "Enrolled face data removed."}), flush=True)


def cmd_verify(camera_device="/dev/video0", timeout_sec=10.0, confidence_threshold=98.0):
    ensure_state_dir()

    if not is_enrolled():
        if os.path.isfile(LEGACY_MODEL_FILE):
            print(json.dumps({
                "status": "not_enrolled",
                "message": "Face ID upgraded to neural engine (YuNet+SFace). Please re-enroll in Settings."
            }), flush=True)
        else:
            print(json.dumps({"status": "not_enrolled", "message": "Face ID has not been registered yet."}), flush=True)
        sys.exit(2)

    detector = get_face_detector()
    recognizer = get_face_recognizer()

    if not detector or not recognizer:
        print(json.dumps({
            "status": "error",
            "message": "Neural face models not found in assets. Please ensure YuNet and SFace ONNX models exist."
        }), flush=True)
        sys.exit(3)

    try:
        enrolled_embeddings = np.load(EMBEDDINGS_FILE)
        if enrolled_embeddings is None or len(enrolled_embeddings) == 0:
            print(json.dumps({"status": "not_enrolled", "message": "No valid face embeddings found."}), flush=True)
            sys.exit(2)
    except Exception as e:
        print(json.dumps({"status": "error", "message": f"Failed to load Face ID embeddings: {e}"}), flush=True)
        sys.exit(4)

    target_cosine_threshold = parse_confidence_threshold(confidence_threshold)

    cap = open_camera(camera_device, notify_ready=True)
    if not cap.isOpened():
        print(json.dumps({"status": "camera_unavailable", "device": str(camera_device)}), flush=True)
        sys.exit(5)

    print(json.dumps({"status": "scanning", "message": "Looking for face..."}), flush=True)

    start_time = time.time()
    match_count = 0
    consecutive_needed = 3

    try:
        while True:
            elapsed = time.time() - start_time
            if elapsed > timeout_sec:
                print(json.dumps({"status": "timeout", "message": "Scan timed out."}), flush=True)
                sys.exit(1)

            ret, frame = cap.read()
            if not ret or frame is None:
                time.sleep(0.03)
                continue

            fh, fw = frame.shape[:2]
            detector.setInputSize((fw, fh))

            _, faces = detector.detect(frame)
            if faces is None or len(faces) == 0:
                enhanced, is_low, _ = enhance_low_light(frame)
                if is_low:
                    _, faces = detector.detect(enhanced)

            if faces is None or len(faces) == 0:
                match_count = max(0, match_count - 1)
                time.sleep(0.03)
                continue

            # Urutkan berdasarkan luas area wajah (ambil wajah utama)
            faces = sorted(faces, key=lambda f: f[2] * f[3], reverse=True)
            primary_face = faces[0]
            x, y, w, h = int(primary_face[0]), int(primary_face[1]), int(primary_face[2]), int(primary_face[3])

            if w < 40 or h < 40 or primary_face[-1] < 0.65:
                match_count = max(0, match_count - 1)
                time.sleep(0.03)
                continue

            # Align & ekstrak feature embedding wajah
            aligned = recognizer.alignCrop(frame, primary_face)
            query_feat = recognizer.feature(aligned)

            # Hitung cosine similarity terhadap seluruh referensi embedding tersimpan
            scores = [
                recognizer.match(query_feat, ref.reshape(1, -1), cv2.FaceRecognizerSF_FR_COSINE)
                for ref in enrolled_embeddings
            ]
            best_similarity = max(scores) if scores else 0.0

            if best_similarity >= target_cosine_threshold:
                match_count += 1
                print(json.dumps({
                    "status": "detected",
                    "confidence": round(float(best_similarity), 3),
                    "matches": match_count
                }), flush=True)

                # Syarat sukses: minimal consecutive_needed match berurutan,
                # atau jika confidence sangat tinggi (misal >= target + 0.20) setelah 2 frame
                if match_count >= consecutive_needed or (match_count >= 2 and best_similarity >= (target_cosine_threshold + 0.20)):
                    username = os.environ.get("USER", "user")
                    print(json.dumps({
                        "status": "success",
                        "confidence": round(float(best_similarity), 3),
                        "user": username,
                        "message": "Face verified successfully"
                    }), flush=True)
                    cap.release()
                    sys.exit(0)
            else:
                match_count = max(0, match_count - 1)
                print(json.dumps({
                    "status": "unrecognized",
                    "confidence": round(float(best_similarity), 3)
                }), flush=True)

            time.sleep(0.03)

    finally:
        cap.release()


def cmd_enroll(camera_device="/dev/video0", samples_needed=24, show_preview=True):
    ensure_state_dir()

    detector = get_face_detector(score_threshold=0.75)
    recognizer = get_face_recognizer()

    if not detector or not recognizer:
        print(json.dumps({
            "status": "error",
            "message": "Model ONNX YuNet atau SFace tidak ditemukan di folder assets."
        }), flush=True)
        sys.exit(1)

    cap = open_camera(camera_device)
    if not cap.isOpened():
        print(json.dumps({"status": "camera_unavailable", "device": str(camera_device)}), flush=True)
        sys.exit(2)

    preview_proc = None
    if show_preview:
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

    # Pembagian fase: Center, Left, Right
    per_phase = max(4, samples_needed // 3)
    PHASES = [
        {"id": "center", "name": "Center", "step": 1, "title": "LOOK STRAIGHT", "tip": "Step 1/3: Look straight ahead into the oval", "target": per_phase, "arc_start": 220, "arc_end": 320, "dir": "center"},
        {"id": "left", "name": "Turn Left", "step": 2, "title": "TURN HEAD LEFT", "tip": "Step 2/3: Slowly turn your head to the left", "target": per_phase, "arc_start": 105, "arc_end": 205, "dir": "left"},
        {"id": "right", "name": "Turn Right", "step": 3, "title": "TURN HEAD RIGHT", "tip": "Step 3/3: Slowly turn your head to the right", "target": per_phase, "arc_start": 335, "arc_end": 435, "dir": "right"}
    ]

    total_samples_needed = sum(p["target"] for p in PHASES)

    print(json.dumps({
        "status": "enrolling",
        "message": "Position your face in front of the camera...",
        "total": total_samples_needed
    }), flush=True)

    enrolled_features = []
    total_collected = 0
    phase_idx = 0
    phase_collected = 0
    last_capture = 0
    sample_preview_saved = False
    transition_frames_left = 0
    transition_title = ""

    center_x, center_y = 320, 225
    radius_x, radius_y = 115, 145

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

            frame = cv2.flip(frame, 1)
            display_frame = frame.copy()
            display_frame[outside] = (display_frame[outside].astype(np.float32) * 0.60).astype(np.uint8)

            cur_phase = PHASES[phase_idx]

            fh, fw = frame.shape[:2]
            detector.setInputSize((fw, fh))

            _, raw_faces = detector.detect(frame)
            faces = []
            if raw_faces is not None and len(raw_faces) > 0:
                for f in raw_faces:
                    fx, fy, fw_box, fh_box = int(f[0]), int(f[1]), int(f[2]), int(f[3])
                    fcx = fx + fw_box / 2
                    score = float(f[-1])
                    if score >= 0.70 and fw_box >= 60 and fh_box >= 60:
                        # Evaluasi posisi agar berada di tengah oval
                        if 180 <= fcx <= 460:
                            faces.append(f)

            face_detected = len(faces) > 0

            # UI Oval guide
            cv2.ellipse(display_frame, (center_x, center_y), (radius_x, radius_y), 0, 0, 360, (38, 38, 42), 2, cv2.LINE_AA)

            # Arc progress segments
            for p_i, p_info in enumerate(PHASES):
                a_start = p_info["arc_start"]
                a_end = p_info["arc_end"]
                a_span = a_end - a_start

                if p_i < phase_idx:
                    cv2.ellipse(display_frame, (center_x, center_y), (radius_x, radius_y), 0, a_start, a_end, (80, 230, 80), 4, cv2.LINE_AA)
                    mid_ang = (a_start + a_end) / 2.0
                    rad = np.radians(mid_ang)
                    mx = int(center_x + (radius_x + 14) * np.cos(rad))
                    my = int(center_y + (radius_y + 14) * np.sin(rad))
                    cv2.circle(display_frame, (mx, my), 9, (20, 20, 24), -1)
                    cv2.circle(display_frame, (mx, my), 9, (80, 230, 80), 1, cv2.LINE_AA)
                    cv2.putText(display_frame, "+", (mx - 4, my + 4), cv2.FONT_HERSHEY_SIMPLEX, 0.38, (80, 230, 80), 1, cv2.LINE_AA)
                elif p_i == phase_idx:
                    pct = min(1.0, phase_collected / p_info["target"])
                    cv2.ellipse(display_frame, (center_x, center_y), (radius_x, radius_y), 0, a_start, a_end, (65, 65, 75), 2, cv2.LINE_AA)
                    if pct > 0:
                        cur_end = int(a_start + a_span * pct)
                        cv2.ellipse(display_frame, (center_x, center_y), (radius_x, radius_y), 0, a_start, cur_end, (100, 240, 80), 4, cv2.LINE_AA)
                else:
                    cv2.ellipse(display_frame, (center_x, center_y), (radius_x, radius_y), 0, a_start, a_end, (45, 45, 50), 2, cv2.LINE_AA)

            pulse = int((np.sin(time.time() * 6.0) + 1.0) * 8)
            if cur_phase["dir"] == "left":
                cv2.putText(display_frame, "<<<", (45 - pulse, 230), cv2.FONT_HERSHEY_SIMPLEX, 0.82, (100, 240, 80), 2, cv2.LINE_AA)
                cv2.putText(display_frame, "TURN LEFT", (25, 255), cv2.FONT_HERSHEY_SIMPLEX, 0.40, (180, 180, 180), 1, cv2.LINE_AA)
            elif cur_phase["dir"] == "right":
                cv2.putText(display_frame, ">>>", (535 + pulse, 230), cv2.FONT_HERSHEY_SIMPLEX, 0.82, (100, 240, 80), 2, cv2.LINE_AA)
                cv2.putText(display_frame, "TURN RIGHT", (525, 255), cv2.FONT_HERSHEY_SIMPLEX, 0.40, (180, 180, 180), 1, cv2.LINE_AA)

            now = time.time()

            if face_detected and transition_frames_left == 0:
                faces = sorted(faces, key=lambda f: f[2] * f[3], reverse=True)
                primary_face = faces[0]
                px, py, pw, ph = int(primary_face[0]), int(primary_face[1]), int(primary_face[2]), int(primary_face[3])

                # Draw targeting corners
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

                if now - last_capture >= 0.16:
                    aligned = recognizer.alignCrop(frame, primary_face)
                    feat = recognizer.feature(aligned)

                    enrolled_features.append(feat)
                    phase_collected += 1
                    total_collected += 1
                    last_capture = now

                    # Simpan thumbnail avatar preview
                    if not sample_preview_saved or cur_phase["id"] == "center":
                        crop_x1 = max(0, px - int(pw * 0.15))
                        crop_y1 = max(0, py - int(ph * 0.20))
                        crop_x2 = min(fw, px + pw + int(pw * 0.15))
                        crop_y2 = min(fh, py + ph + int(ph * 0.15))
                        color_roi = frame[crop_y1:crop_y2, crop_x1:crop_x2]
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

                    if phase_collected >= cur_phase["target"]:
                        if phase_idx < len(PHASES) - 1:
                            transition_frames_left = 18
                            transition_title = f"{cur_phase['name']} Angle Captured!"
                            phase_idx += 1
                            phase_collected = 0
                        else:
                            phase_idx = len(PHASES)
                            break

            if transition_frames_left > 0:
                transition_frames_left -= 1
                cv2.rectangle(display_frame, (160, 200), (480, 255), (18, 18, 22), -1)
                cv2.rectangle(display_frame, (160, 200), (480, 255), (100, 240, 80), 1)
                cv2.putText(display_frame, f"+ {transition_title}", (180, 235), cv2.FONT_HERSHEY_SIMPLEX, 0.58, (100, 240, 80), 2, cv2.LINE_AA)

            # Header bar
            cv2.rectangle(display_frame, (0, 0), (640, 52), (18, 18, 22), -1)
            cv2.line(display_frame, (0, 52), (640, 52), (50, 50, 58), 1)
            cv2.putText(display_frame, "APPLE-STYLE FACE ID SETUP", (22, 23), cv2.FONT_HERSHEY_SIMPLEX, 0.48, (160, 160, 170), 1, cv2.LINE_AA)

            p1_str = "[+] 1.Center" if phase_idx > 0 else ("[● 1.Center]" if phase_idx == 0 else "[○ 1.Center]")
            p2_str = "[+] 2.Left" if phase_idx > 1 else ("[● 2.Left]" if phase_idx == 1 else "[○ 2.Left]")
            p3_str = "[+] 3.Right" if phase_idx > 2 else ("[● 3.Right]" if phase_idx == 2 else "[○ 3.Right]")

            cv2.putText(display_frame, f"{p1_str}  {p2_str}  {p3_str}", (22, 44), cv2.FONT_HERSHEY_SIMPLEX, 0.52, (255, 255, 255), 1, cv2.LINE_AA)
            pct = int((total_collected / total_samples_needed) * 100)
            cv2.putText(display_frame, f"{pct}%", (580, 44), cv2.FONT_HERSHEY_SIMPLEX, 0.54, (100, 240, 80), 2, cv2.LINE_AA)

            # Footer progress bar
            cv2.rectangle(display_frame, (0, 420), (640, 480), (18, 18, 22), -1)
            cv2.line(display_frame, (0, 420), (640, 420), (50, 50, 58), 1)

            cv2.rectangle(display_frame, (20, 426), (620, 432), (38, 38, 44), -1)
            bar_w = int(600 * (total_collected / total_samples_needed))
            if bar_w > 0:
                cv2.rectangle(display_frame, (20, 426), (20 + bar_w, 432), (100, 240, 80), -1)

            guide = cur_phase["tip"] if face_detected else f"{cur_phase['tip']} (Position face in frame)"
            guide_color = (100, 240, 80) if face_detected else (200, 200, 200)
            cv2.putText(display_frame, guide, (22, 458), cv2.FONT_HERSHEY_SIMPLEX, 0.54, guide_color, 1, cv2.LINE_AA)

            if preview_proc and preview_proc.stdin:
                try:
                    preview_proc.stdin.write(display_frame.tobytes())
                    preview_proc.stdin.flush()
                except (BrokenPipeError, OSError):
                    print(json.dumps({"status": "cancelled", "message": "Enrollment cancelled by user."}), flush=True)
                    sys.exit(0)

            time.sleep(0.025)

        print(json.dumps({
            "status": "review",
            "message": "All facial angles verified! Reviewing registration...",
            "progress": 1.0
        }), flush=True)

        username = os.environ.get("USER", "user")
        confirm_duration = 3.6
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

            overlay = frame.copy()
            cv2.rectangle(overlay, (0, 0), (640, 480), (10, 10, 14), -1)
            display_frame = cv2.addWeighted(overlay, 0.88, frame, 0.12, 0)

            card_x1, card_y1, card_x2, card_y2 = 35, 25, 605, 455
            cv2.rectangle(display_frame, (card_x1, card_y1), (card_x2, card_y2), (18, 18, 24), -1)
            cv2.rectangle(display_frame, (card_x1, card_y1), (card_x2, card_y2), (80, 230, 80), 2, cv2.LINE_AA)

            cv2.putText(display_frame, "FACE ID ENROLLMENT CONFIRMATION", (70, 62), cv2.FONT_HERSHEY_SIMPLEX, 0.64, (100, 240, 80), 2, cv2.LINE_AA)
            cv2.putText(display_frame, "All 3 facial angles verified with neural embeddings (SFace)", (70, 86), cv2.FONT_HERSHEY_SIMPLEX, 0.44, (180, 180, 180), 1, cv2.LINE_AA)
            cv2.line(display_frame, (50, 98), (590, 98), (45, 45, 55), 1)

            badge_y = 132
            cv2.rectangle(display_frame, (55, badge_y - 20), (215, badge_y + 12), (25, 45, 30), -1)
            cv2.rectangle(display_frame, (55, badge_y - 20), (215, badge_y + 12), (80, 230, 80), 1)
            cv2.putText(display_frame, f"+ Frontal ({per_phase}/{per_phase})", (68, badge_y), cv2.FONT_HERSHEY_SIMPLEX, 0.44, (100, 240, 80), 1, cv2.LINE_AA)

            cv2.rectangle(display_frame, (240, badge_y - 20), (400, badge_y + 12), (25, 45, 30), -1)
            cv2.rectangle(display_frame, (240, badge_y - 20), (400, badge_y + 12), (80, 230, 80), 1)
            cv2.putText(display_frame, f"+ Left Turn ({per_phase}/{per_phase})", (248, badge_y), cv2.FONT_HERSHEY_SIMPLEX, 0.44, (100, 240, 80), 1, cv2.LINE_AA)

            cv2.rectangle(display_frame, (425, badge_y - 20), (585, badge_y + 12), (25, 45, 30), -1)
            cv2.rectangle(display_frame, (425, badge_y - 20), (585, badge_y + 12), (80, 230, 80), 1)
            cv2.putText(display_frame, f"+ Right Turn ({per_phase}/{per_phase})", (432, badge_y), cv2.FONT_HERSHEY_SIMPLEX, 0.44, (100, 240, 80), 1, cv2.LINE_AA)

            mid_x, mid_y = 320, 240
            if preview_thumb is not None:
                tx1 = mid_x - 55
                ty1 = mid_y - 55
                display_frame[ty1:ty1+110, tx1:tx1+110] = preview_thumb
                cv2.rectangle(display_frame, (tx1 - 2, ty1 - 2), (tx1 + 112, ty1 + 112), (80, 230, 80), 2, cv2.LINE_AA)

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
            cv2.putText(display_frame, f"{total_collected} SFace Neural Embeddings (128-d)", (180, mid_y + 102), cv2.FONT_HERSHEY_SIMPLEX, 0.44, (150, 150, 150), 1, cv2.LINE_AA)

            rem = max(0.1, confirm_duration - elapsed)
            cv2.line(display_frame, (50, 395), (590, 395), (45, 45, 55), 1)

            bar_w = int(500 * (elapsed / confirm_duration))
            cv2.rectangle(display_frame, (70, 410), (570, 418), (35, 35, 40), -1)
            if bar_w > 0:
                cv2.rectangle(display_frame, (70, 410), (70 + bar_w, 418), (100, 240, 80), -1)

            conf_txt = f"Auto-saving profile in {rem:.1f}s...  (Close window to cancel)"
            cv2.putText(display_frame, conf_txt, (135, 438), cv2.FONT_HERSHEY_SIMPLEX, 0.46, (200, 200, 200), 1, cv2.LINE_AA)

            if preview_proc and preview_proc.stdin:
                try:
                    preview_proc.stdin.write(display_frame.tobytes())
                    preview_proc.stdin.flush()
                except (BrokenPipeError, OSError):
                    print(json.dumps({"status": "cancelled", "message": "Enrollment cancelled by user."}), flush=True)
                    sys.exit(0)

            time.sleep(0.04)

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

        print(json.dumps({"status": "training", "message": "Saving facial recognition embeddings..."}), flush=True)

        embeddings_matrix = np.vstack(enrolled_features).astype(np.float32)
        np.save(EMBEDDINGS_FILE, embeddings_matrix)

        # Hapus model XML lama jika ada
        if os.path.isfile(LEGACY_MODEL_FILE):
            try:
                os.remove(LEGACY_MODEL_FILE)
            except Exception:
                pass

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
    parser = argparse.ArgumentParser(description="Quickshell Face ID Helper (YuNet + SFace)")
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
    enroll_p.add_argument("--samples", type=int, default=24)
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
