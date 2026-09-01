#!/usr/bin/env python3
import os
import sys
import json
import subprocess
import shutil
import re

HOME = os.path.expanduser("~")

def run_proc(args, timeout=2.5):
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return r.stdout.strip()
    except Exception:
        return ""

def get_data_dirs(subfolder=""):
    """
    Discovers all valid data directories following XDG specifications,
    NixOS user/system profiles, and legacy home directories.
    """
    dirs = []
    seen = set()

    def add_dir(d):
        if d and os.path.isdir(d) and d not in seen:
            seen.add(d)
            dirs.append(d)

    # 1. User XDG_DATA_HOME or ~/.local/share
    data_home = os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local/share")
    if data_home:
        add_dir(os.path.join(data_home, subfolder) if subfolder else data_home)

    # 2. Legacy home directories (~/.themes, ~/.icons, ~/.fonts, etc.)
    if subfolder in ["themes", "icons", "fonts", "pixmaps"]:
        add_dir(os.path.join(HOME, f".{subfolder}"))

    # 3. Nix and System aggregated profiles (contain full package merges)
    user = os.environ.get("USER") or os.path.basename(HOME)
    standard_bases = [
        f"/etc/profiles/per-user/{user}/share",
        "/run/current-system/sw/share",
        os.path.join(HOME, ".nix-profile/share"),
        os.path.join(HOME, ".local/state/nix/profile/share"),
        "/nix/profile/share",
        "/nix/var/nix/profiles/default/share",
        "/usr/local/share",
        "/usr/share"
    ]
    for b in standard_bases:
        add_dir(os.path.join(b, subfolder) if subfolder else b)

    # 4. Directories from XDG_DATA_DIRS
    xdg_dirs = [x.strip() for x in os.environ.get("XDG_DATA_DIRS", "").split(":") if x.strip()]
    for d in xdg_dirs:
        add_dir(os.path.join(d, subfolder) if subfolder else d)

    return dirs

def get_gsettings(schema, key):
    raw = run_proc(["gsettings", "get", schema, key], timeout=1.5)
    if raw and not raw.startswith("No such schema") and not raw.startswith("GLib-GIO-ERROR"):
        if (raw.startswith("'") and raw.endswith("'")) or (raw.startswith('"') and raw.endswith('"')):
            return raw[1:-1]
        return raw
    # Fallback to dconf read if gsettings schema query failed
    dpath = "/" + schema.replace(".", "/") + "/" + key
    raw_dconf = run_proc(["dconf", "read", dpath], timeout=1.0)
    if raw_dconf:
        if (raw_dconf.startswith("'") and raw_dconf.endswith("'")) or (raw_dconf.startswith('"') and raw_dconf.endswith('"')):
            return raw_dconf[1:-1]
        return raw_dconf
    return ""

def set_gsettings(schema, key, val):
    if isinstance(val, bool):
        val_str = "true" if val else "false"
        dconf_val = "true" if val else "false"
    elif isinstance(val, (int, float)):
        val_str = str(val)
        dconf_val = str(val)
    else:
        clean = str(val).strip("'\"")
        val_str = clean
        dconf_val = f"'{clean}'"
    run_proc(["gsettings", "set", schema, key, val_str], timeout=2.0)
    dpath = "/" + schema.replace(".", "/") + "/" + key
    run_proc(["dconf", "write", dpath, dconf_val], timeout=2.0)

def is_nix_store_managed(path):
    """
    Checks if a file or directory is managed directly by Home Manager / NixOS read-only store.
    Guarantees that nix store files, profiles, and home-manager-files links are never modified.
    """
    try:
        if not os.path.exists(path) and not os.path.islink(path):
            return False
        # If the parent directory itself is in a read-only system or nix path
        parent_real = os.path.realpath(os.path.dirname(path))
        if parent_real.startswith("/nix/store") or parent_real.startswith("/run/current-system") or parent_real.startswith("/etc/profiles"):
            return True
        if os.path.islink(path):
            target = os.readlink(path)
            if "home-manager-files" in target or (target.startswith("/nix/store") and "home-manager" in target):
                return True
        elif os.path.exists(path):
            real = os.path.realpath(path)
            if "home-manager-files" in real:
                return True
    except Exception:
        pass
    return False

def update_gtk_ini(file_path, key_values):
    # NEVER overwrite or unlink files managed by Nix store / Home Manager
    if is_nix_store_managed(file_path):
        return

    parent_dir = os.path.dirname(file_path)
    if not os.path.exists(parent_dir):
        try:
            os.makedirs(parent_dir, exist_ok=True)
        except Exception:
            return

    lines = []
    if os.path.exists(file_path):
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                lines = f.readlines()
        except Exception:
            lines = []
    
    settings_idx = -1
    for i, line in enumerate(lines):
        if line.strip() == "[Settings]":
            settings_idx = i
            break
    
    if settings_idx == -1:
        lines.insert(0, "[Settings]\n")
        settings_idx = 0
        
    for k, v in key_values.items():
        found = False
        prefix = f"{k}="
        for i in range(settings_idx + 1, len(lines)):
            if lines[i].strip().startswith("["):
                break
            if lines[i].strip().startswith(prefix):
                lines[i] = f"{k}={v}\n"
                found = True
                break
        if not found:
            lines.insert(settings_idx + 1, f"{k}={v}\n")
            
    try:
        if os.path.islink(file_path):
            os.unlink(file_path)
        with open(file_path, "w", encoding="utf-8") as f:
            f.writelines(lines)
    except Exception:
        try:
            if os.path.exists(file_path):
                os.remove(file_path)
            with open(file_path, "w", encoding="utf-8") as f:
                f.writelines(lines)
        except Exception:
            pass

def update_xsettingsd(key_values):
    conf_path = os.path.join(HOME, ".config/xsettingsd/xsettingsd.conf")
    if is_nix_store_managed(conf_path):
        run_proc(["pkill", "-HUP", "xsettingsd"], timeout=0.5)
        return

    if not os.path.exists(os.path.dirname(conf_path)):
        try:
            os.makedirs(os.path.dirname(conf_path), exist_ok=True)
        except Exception:
            return
    lines = []
    if os.path.exists(conf_path):
        try:
            with open(conf_path, "r", encoding="utf-8") as f:
                lines = f.readlines()
        except Exception:
            lines = []
    for k, v in key_values.items():
        found = False
        prefix = f"{k} "
        formatted_val = f'"{v}"' if isinstance(v, str) else str(v)
        new_line = f"{k} {formatted_val}\n"
        for i in range(len(lines)):
            if lines[i].strip().startswith(prefix):
                lines[i] = new_line
                found = True
                break
        if not found:
            lines.append(new_line)
    try:
        if os.path.islink(conf_path):
            os.unlink(conf_path)
        with open(conf_path, "w", encoding="utf-8") as f:
            f.writelines(lines)
        run_proc(["pkill", "-HUP", "xsettingsd"], timeout=0.5)
    except Exception:
        pass

def update_gtk2(key_values):
    gtk2_path = os.path.join(HOME, ".gtkrc-2.0")
    if is_nix_store_managed(gtk2_path):
        return
    lines = []
    if os.path.exists(gtk2_path):
        try:
            with open(gtk2_path, "r", encoding="utf-8") as f:
                lines = f.readlines()
        except Exception:
            lines = []
    for k, v in key_values.items():
        found = False
        prefix = f"{k}="
        new_line = f'{k}="{v}"\n'
        for i in range(len(lines)):
            if lines[i].strip().startswith(prefix):
                lines[i] = new_line
                found = True
                break
        if not found:
            lines.append(new_line)
    try:
        if os.path.islink(gtk2_path):
            os.unlink(gtk2_path)
        with open(gtk2_path, "w", encoding="utf-8") as f:
            f.writelines(lines)
    except Exception:
        pass

def update_default_icon_theme(icon_theme, cursor_theme=None):
    default_dir = os.path.join(HOME, ".icons/default")
    idx_path = os.path.join(default_dir, "index.theme")
    if is_nix_store_managed(idx_path):
        return
    try:
        os.makedirs(default_dir, exist_ok=True)
        cur_icon = icon_theme or get_gsettings("org.gnome.desktop.interface", "icon-theme") or "MacTahoe"
        cur_cursor = cursor_theme or get_gsettings("org.gnome.desktop.interface", "cursor-theme") or "MacTahoe-dark"
        inherits_parts = []
        if cur_cursor:
            inherits_parts.append(cur_cursor)
        if cur_icon and cur_icon not in inherits_parts:
            inherits_parts.append(cur_icon)
        for fb in ["MacTahoe", "WhiteSur", "Adwaita", "Pop", "breeze", "hicolor"]:
            if fb not in inherits_parts:
                inherits_parts.append(fb)
        inherits_val = ",".join(inherits_parts)
        new_content = f"[Icon Theme]\nName=Default\nComment=Default Icon Theme\nInherits={inherits_val}\n"
        if os.path.islink(idx_path):
            os.unlink(idx_path)
        with open(idx_path, "w", encoding="utf-8") as f:
            f.write(new_content)
    except Exception:
        pass

def apply_icon_theme_links(icon_theme_name=None):
    search_bases = get_data_dirs("icons")
    themes_found = set()
    for base in search_bases:
        if base in [os.path.join(HOME, ".icons"), os.path.join(HOME, ".local/share/icons")]:
            continue
        try:
            for item in os.listdir(base):
                p = os.path.join(base, item)
                if os.path.isdir(p) or (os.path.islink(p) and os.path.exists(p)):
                    themes_found.add(item)
        except Exception:
            pass

    if icon_theme_name:
        themes_found.add(icon_theme_name)
        if "MacTahoe" in icon_theme_name:
            themes_found.update(["MacTahoe", "MacTahoe-dark", "MacTahoe-light"])
        elif "WhiteSur" in icon_theme_name:
            themes_found.update(["WhiteSur", "WhiteSur-dark", "WhiteSur-light"])
        elif "breeze" in icon_theme_name.lower():
            themes_found.update(["breeze", "breeze-dark", "Breeze_Light", "breeze_cursors"])

    themes_found.update(["hicolor", "Adwaita", "Pop", "breeze", "Cosmic"])

    user = os.environ.get("USER") or os.path.basename(HOME)
    candidate_bases = []
    user_profile = f"/etc/profiles/per-user/{user}/share/icons"
    sys_profile = "/run/current-system/sw/share/icons"
    if os.path.isdir(user_profile):
        candidate_bases.append(user_profile)
    if os.path.isdir(sys_profile):
        candidate_bases.append(sys_profile)
    for base in search_bases:
        if base not in candidate_bases and base not in [os.path.join(HOME, ".icons"), os.path.join(HOME, ".local/share/icons")]:
            candidate_bases.append(base)

    for tname in themes_found:
        if not tname:
            continue
        src_dir = ""
        for base in candidate_bases:
            p = os.path.join(base, tname)
            if (os.path.isdir(p) or os.path.islink(p)) and os.path.exists(p):
                src_dir = p
                break
        if not src_dir:
            continue

        for dest_base in [os.path.join(HOME, ".icons"), os.path.join(HOME, ".local/share/icons")]:
            os.makedirs(dest_base, exist_ok=True)
            dest_link = os.path.join(dest_base, tname)
            
            # NEVER modify or delete files/symlinks managed by Nix store / Home Manager
            if is_nix_store_managed(dest_link):
                continue
                
            if os.path.isdir(dest_link) and not os.path.islink(dest_link):
                try:
                    is_empty = True
                    for root_d, d_list, f_list in os.walk(dest_link):
                        if f_list:
                            is_empty = False
                            break
                    if is_empty:
                        shutil.rmtree(dest_link)
                except Exception:
                    pass

            if os.path.islink(dest_link):
                try:
                    if not os.path.exists(dest_link) or os.path.realpath(dest_link) != os.path.realpath(src_dir):
                        os.unlink(dest_link)
                except Exception:
                    pass
                    
            if not os.path.exists(dest_link) and not os.path.islink(dest_link):
                try:
                    os.symlink(src_dir, dest_link)
                except Exception:
                    pass

def get_gtk_themes():
    search_paths = get_data_dirs("themes")
    themes = set()
    for p in search_paths:
        try:
            for d in os.listdir(p):
                full = os.path.join(p, d)
                if os.path.isdir(full):
                    if (os.path.exists(os.path.join(full, "gtk-3.0")) or 
                        os.path.exists(os.path.join(full, "gtk-4.0")) or 
                        os.path.exists(os.path.join(full, "gtk-2.0")) or
                        os.path.exists(os.path.join(full, "index.theme"))):
                        themes.add(d)
        except Exception:
            pass
    theme_list = sorted(list(themes))
    if not theme_list:
        theme_list = ["Adwaita", "Tahoe-Dark", "Tahoe-Light", "Default"]
    return theme_list

def get_icon_and_cursor_themes():
    search_paths = get_data_dirs("icons")
    icons = set()
    cursors = set()
    for p in search_paths:
        try:
            for d in os.listdir(p):
                full = os.path.join(p, d)
                if os.path.isdir(full):
                    if os.path.exists(os.path.join(full, "cursors")):
                        cursors.add(d)
                    if os.path.exists(os.path.join(full, "index.theme")):
                        sub = os.listdir(full)
                        has_real_icons = any(f in sub for f in [
                            "apps", "apps@2x", "places", "places@2x", "mimes", "mimes@2x",
                            "actions", "actions@2x", "categories", "categories@2x", "scalable"
                        ])
                        if has_real_icons:
                            icons.add(d)
        except Exception:
            pass
    icon_list = sorted(list(icons))
    cursor_list = sorted(list(cursors))
    if not icon_list:
        icon_list = ["MacTahoe", "WhiteSur", "breeze", "hicolor"]
    if not cursor_list:
        cursor_list = ["MacTahoe-dark", "MacTahoe-light", "Bibata-Modern-Classic", "Adwaita"]
    return icon_list, cursor_list

def get_fonts():
    try:
        r = run_proc(["fc-list", ":", "family"], timeout=4.0)
        if not r:
            for fc_bin in ["/run/current-system/sw/bin/fc-list", "/etc/profiles/per-user/" + (os.environ.get("USER") or "user") + "/bin/fc-list", "/usr/bin/fc-list"]:
                if os.path.exists(fc_bin):
                    r = run_proc([fc_bin, ":", "family"], timeout=4.0)
                    if r:
                        break

        if not r:
            return ["Liga SFMonoNerdFont", "SF Pro Display", "JetBrainsMono Nerd Font", "Adwaita Sans", "Inter", "Noto Sans"], ["Liga SFMonoNerdFont", "JetBrainsMono Nerd Font", "Adwaita Mono"]
        
        all_fonts = set()
        for line in r.splitlines():
            for part in line.split(","):
                name = part.strip()
                if name and not name.startswith(".") and len(name) < 45:
                    # Clean out overly specific weights to keep family names clean
                    clean_name = re.sub(r"\s+(ExtraLight|UltraLight|Light|Thin|Medium|SemiBold|DemiBold|Bold|ExtraBold|Black|Heavy|Italic|Book|Regular)$", "", name).strip()
                    if clean_name:
                        all_fonts.add(clean_name)
        
        popular_preferred = [
            "Liga SFMonoNerdFont", "SF Pro Display", "SF Pro Text", "Inter", "JetBrainsMono Nerd Font",
            "JetBrains Mono", "Adwaita Sans", "Adwaita Mono", "FiraCode Nerd Font", "Fira Code",
            "Roboto", "Ubuntu", "Cantarell", "Noto Sans", "Noto Sans Mono", "Geist", "Cascadia Code"
        ]
        
        proportional = []
        monospace = []
        
        for name in sorted(list(all_fonts)):
            low = name.lower()
            if any(m in low for m in ["mono", "code", "sfmono", "nerd font mono", "terminal", "hack", "iosevka", "consolas"]):
                monospace.append(name)
            else:
                proportional.append(name)
        
        def sort_with_preferred(items):
            pref = [p for p in popular_preferred if p in items]
            rest = [i for i in items if i not in pref]
            return pref + sorted(rest)
        
        return sort_with_preferred(list(all_fonts)), sort_with_preferred(monospace)
    except Exception:
        return ["Liga SFMonoNerdFont", "Inter", "Adwaita Sans", "Noto Sans"], ["Liga SFMonoNerdFont", "Adwaita Mono", "JetBrainsMono Nerd Font"]

def parse_font_spec(font_str, default_family="Liga SFMonoNerdFont", default_size=11):
    if not font_str:
        return default_family, default_size
    parts = font_str.strip().split()
    if len(parts) >= 2:
        try:
            size_val = int(float(parts[-1]))
            fam = " ".join(parts[:-1])
            clean_fam = re.sub(r"\s+(Regular|Medium|Light|Bold|SemiBold|DemiBold|Italic)$", "", fam)
            return clean_fam if clean_fam else fam, size_val
        except ValueError:
            pass
    return font_str, default_size

def get_theme_dirs_with_inheritance(theme_name):
    dirs = []
    seen = set()
    search_bases = get_data_dirs("icons")
    
    def add_theme(tname):
        if not tname or tname in seen:
            return
        seen.add(tname)
        for base in search_bases:
            tdir = os.path.join(base, tname)
            if os.path.isdir(tdir):
                dirs.append(tdir)
                idx = os.path.join(tdir, "index.theme")
                if os.path.exists(idx):
                    try:
                        with open(idx, "r", encoding="utf-8", errors="ignore") as f:
                            for line in f:
                                if line.strip().startswith("Inherits="):
                                    for inh in line.strip()[9:].split(","):
                                        inh_clean = inh.strip()
                                        if inh_clean:
                                            add_theme(inh_clean)
                    except Exception:
                        pass
    add_theme(theme_name)
    if "MacTahoe" in theme_name:
        add_theme("MacTahoe")
    if "WhiteSur" in theme_name:
        add_theme("WhiteSur")
    if "breeze" in theme_name.lower():
        add_theme("breeze")
    add_theme("hicolor")
    # Standard desktop theme fallbacks to ensure full icon coverage on NixOS
    for fallback in ["Adwaita", "breeze", "breeze-dark", "gnome", "Pop", "WhiteSur", "WhiteSur-dark", "Cosmic", "locolor", "ubuntu-mono-dark"]:
        add_theme(fallback)
    for pix in get_data_dirs("pixmaps"):
        if os.path.isdir(pix) and pix not in dirs:
            dirs.append(pix)
    # Loose icons directories
    for base in search_bases:
        if os.path.isdir(base) and base not in dirs:
            dirs.append(base)
    return dirs

def get_icon_category_score(path):
    p = path.lower()
    score = 0
    if "/apps/" in p or "/apps@2x/" in p or "/apps@3x/" in p or "/applications/" in p:
        score += 1000
    elif "/categories/" in p or "/categories@2x/" in p:
        score += 800
    elif "/devices/" in p or "/devices@2x/" in p:
        score += 600
    elif "/places/" in p:
        score += 500
    elif "/preferences/" in p:
        score += 400
    elif "/actions/" in p:
        score += 200
    elif "/status/" in p:
        score += 100
        
    if "scalable" in p:
        score += 50
    elif "256" in p or "128" in p:
        score += 45
    elif "64" in p or "48" in p:
        score += 40
    elif "32" in p:
        score += 30
    elif "24" in p or "22" in p:
        score += 20
    elif "16" in p:
        score += 10
        
    if "symbolic" in p:
        score -= 150
        
    return score

def build_and_save_icon_cache(theme_name, force_rebuild=False):
    cache_dir = os.path.join(HOME, ".cache/quickshell")
    themes_dir = os.path.join(cache_dir, "themes")
    os.makedirs(themes_dir, exist_ok=True)
    cache_file = os.path.join(cache_dir, "icon_theme_cache.json")
    theme_cache_file = os.path.join(themes_dir, f"{theme_name}.json")

    if not force_rebuild and os.path.exists(theme_cache_file) and os.path.getsize(theme_cache_file) > 1000:
        try:
            with open(theme_cache_file, "r", encoding="utf-8") as tf:
                cache = json.load(tf)
            with open(cache_file, "w", encoding="utf-8") as f:
                json.dump(cache, f)
            return cache
        except Exception:
            pass

    cache = {}
    scores = {}
    search_dirs = get_theme_dirs_with_inheritance(theme_name)
    search_bases = set(get_data_dirs("icons"))
    ext_order = [".svg", ".png", ".xpm"]
    scanned_real_paths = set()
    
    for dir_idx, p in enumerate(search_dirs):
        real_p = os.path.realpath(p)
        if real_p in scanned_real_paths:
            continue
        scanned_real_paths.add(real_p)

        dir_weight = max(0, (len(search_dirs) - dir_idx) * 2000)
        # If p is a top-level icons search base, only inspect loose files in top level
        walk_iter = [(p, [], [f for f in os.listdir(p) if os.path.isfile(os.path.join(p, f))])] if p in search_bases else os.walk(p)
        for root, dirs, files in walk_iter:
            for f in files:
                name, ext = os.path.splitext(f)
                ext = ext.lower()
                if ext in ext_order:
                    full_path = os.path.join(root, f)
                    sc = dir_weight + get_icon_category_score(full_path)
                    name_lower = name.lower()
                    
                    keys_to_set = [name_lower]
                    if "." in name_lower:
                        parts = name_lower.split(".")
                        keys_to_set.append(parts[-1])
                        keys_to_set.append(name_lower.replace(".", "-"))
                        if name_lower.startswith("org.gnome."):
                            keys_to_set.append("gnome-" + name_lower[10:])
                        if name_lower.startswith("org.kde."):
                            keys_to_set.append(name_lower[8:])
                        if name_lower.startswith("com.system76."):
                            keys_to_set.append(name_lower[13:])
                    if "-" in name_lower:
                        parts_dash = name_lower.split("-")
                        keys_to_set.append(parts_dash[0])
                        keys_to_set.append(parts_dash[-1])
                        if "-symbolic" in name_lower:
                            keys_to_set.append(name_lower.replace("-symbolic", ""))
                    if "_symbolic" in name_lower:
                        keys_to_set.append(name_lower.replace("_symbolic", ""))
                        
                    for k in keys_to_set:
                        if k and (k not in cache or sc > scores.get(k, 0)):
                            cache[k] = full_path
                            scores[k] = sc
                            
    # Common desktop app aliases for specialized entries
    aliases = {
        "preferences-system": "preferences-desktop",
        "preferences-desktop": "preferences-system",
        "system-settings": "preferences-system",
        "settings": "preferences-system",
        "quickshell-settings": "preferences-system",
        "gnome-control-center": "preferences-system",
        "org.gnome.settings": "preferences-system",
        "org.kde.systemsettings": "preferences-system",
        "systemsettings": "preferences-system",
        "blueman-manager": "blueman",
        "blueman-adapters": "blueman-device",
        "bvnc": "network-wired",
        "bssh": "network-wired",
        "avahi-discover": "network-wired",
        "claude-desktop": "claude",
        "claude": "com.anthropic.claude",
        "com.anthropic.claude": "claude-desktop",
        "com.mattjakeman.extensionmanager": "extensionmanager",
        "com.mitchellh.ghostty": "ghostty",
        "ghostty": "com.mitchellh.ghostty",
        "com.obsproject.studio": "obs",
        "obs": "com.obsproject.studio",
        "dev.zed.zed": "zed",
        "zed": "dev.zed.zed",
        "org.gnome.tweaks": "gnome-tweaks",
        "gnome-tweaks": "org.gnome.tweaks",
        "org.gnome.texteditor": "gnome-text-editor",
        "org.gnome.simplescan": "simple-scan",
        "org.gnome.systemmonitor": "gnome-system-monitor",
        "org.kde.kdeconnect.app": "kdeconnect",
        "org.kde.kdeconnect.handler": "kdeconnect",
        "org.kde.kdeconnect.daemon": "kdeconnect",
        "org.kde.kdeconnect.sms": "kdeconnect",
        "org.kde.kdeconnect.nonplasma": "kdeconnect",
        "kdeconnect-app": "kdeconnect",
        "kdeconnect-indicator": "kdeconnect",
        "kdeconnect-sms": "kdeconnect",
        "nwg-look": "preferences-desktop-theme",
        "rofi": "system-search",
        "rofi-theme-selector": "preferences-desktop-theme",
        "preferences-system-network": "network-wired",
        "preferences-desktop-theme": "preferences-desktop",
        "antigravity-ide": "antigravity",
        "helium": "web-browser",
        "winbox": "/etc/profiles/per-user/" + (os.environ.get("USER") or "user") + "/share/icons/winbox.png"
    }
    for alias_k, target_k in aliases.items():
        if alias_k not in cache:
            if target_k.startswith("/"):
                if os.path.exists(target_k):
                    cache[alias_k] = target_k
            elif target_k in cache:
                cache[alias_k] = cache[target_k]
        if not target_k.startswith("/") and target_k not in cache and alias_k in cache:
            cache[target_k] = cache[alias_k]
            
    cache_dir = os.path.join(HOME, ".cache/quickshell")
    themes_dir = os.path.join(cache_dir, "themes")
    os.makedirs(themes_dir, exist_ok=True)
    cache_file = os.path.join(cache_dir, "icon_theme_cache.json")
    theme_cache_file = os.path.join(themes_dir, f"{theme_name}.json")

    try:
        with open(theme_cache_file, "w", encoding="utf-8") as tf:
            json.dump(cache, tf)
        with open(cache_file, "w", encoding="utf-8") as f:
            json.dump(cache, f)
    except Exception:
        pass
    return cache

def query_all():
    gtk_themes = get_gtk_themes()
    icon_themes, cursor_themes = get_icon_and_cursor_themes()
    system_fonts, mono_fonts = get_fonts()

    schema = "org.gnome.desktop.interface"
    cur_gtk = get_gsettings(schema, "gtk-theme") or (gtk_themes[0] if gtk_themes else "Adwaita")
    cur_icon = get_gsettings(schema, "icon-theme") or (icon_themes[0] if icon_themes else "Adwaita")
    cur_cursor = get_gsettings(schema, "cursor-theme") or (cursor_themes[0] if cursor_themes else "Adwaita")
    
    cur_cursor_size_raw = get_gsettings(schema, "cursor-size")
    try:
        cur_cursor_size = int(cur_cursor_size_raw)
    except Exception:
        cur_cursor_size = 24
        
    cur_font_str = get_gsettings(schema, "font-name") or "Liga SFMonoNerdFont Medium 11"
    cur_doc_font_str = get_gsettings(schema, "document-font-name") or "Adwaita Sans 12"
    cur_mono_font_str = get_gsettings(schema, "monospace-font-name") or "Adwaita Mono 11"
    
    cur_font_fam, cur_font_sz = parse_font_spec(cur_font_str, "Liga SFMonoNerdFont", 11)
    cur_doc_fam, cur_doc_sz = parse_font_spec(cur_doc_font_str, "Adwaita Sans", 12)
    cur_mono_fam, cur_mono_sz = parse_font_spec(cur_mono_font_str, "Adwaita Mono", 11)
    
    cur_color_scheme = get_gsettings(schema, "color-scheme") or "default"
    cur_hinting = get_gsettings(schema, "font-hinting") or "slight"
    cur_antialiasing = get_gsettings(schema, "font-antialiasing") or "grayscale"
    
    cur_scaling_raw = get_gsettings(schema, "text-scaling-factor")
    try:
        cur_scaling = float(cur_scaling_raw) if cur_scaling_raw else 1.0
    except Exception:
        cur_scaling = 1.0

    # Ensure icon cache is written for active theme
    build_and_save_icon_cache(cur_icon)

    return {
        "gtk_themes": [{"id": t, "label": t} for t in gtk_themes],
        "icon_themes": [{"id": i, "label": i} for i in icon_themes],
        "cursor_themes": [{"id": c, "label": c} for c in cursor_themes],
        "cursor_sizes": [16, 24, 32, 36, 48, 64],
        "system_fonts": [{"id": f, "label": f} for f in system_fonts[:80]],
        "monospace_fonts": [{"id": f, "label": f} for f in mono_fonts[:60]],
        "current": {
            "gtk_theme": cur_gtk,
            "icon_theme": cur_icon,
            "cursor_theme": cur_cursor,
            "cursor_size": cur_cursor_size,
            "color_scheme": cur_color_scheme,
            "font_family": cur_font_fam,
            "font_size": cur_font_sz,
            "font_raw": cur_font_str,
            "doc_font_family": cur_doc_fam,
            "doc_font_size": cur_doc_sz,
            "doc_font_raw": cur_doc_font_str,
            "mono_font_family": cur_mono_fam,
            "mono_font_size": cur_mono_sz,
            "mono_font_raw": cur_mono_font_str,
            "font_hinting": cur_hinting,
            "font_antialiasing": cur_antialiasing,
            "text_scaling_factor": cur_scaling
        }
    }

def apply_gtk_theme_links(theme_name):
    theme_path = ""
    for base in get_data_dirs("themes"):
        p = os.path.join(base, theme_name)
        if os.path.isdir(p):
            theme_path = p
            break

    gtk4_dir = os.path.join(HOME, ".config/gtk-4.0")
    gtk3_dir = os.path.join(HOME, ".config/gtk-3.0")
    os.makedirs(gtk4_dir, exist_ok=True)
    os.makedirs(gtk3_dir, exist_ok=True)

    gtk4_theme_dir = os.path.join(theme_path, "gtk-4.0") if theme_path else ""
    gtk3_theme_dir = os.path.join(theme_path, "gtk-3.0") if theme_path else ""

    # 1. Update GTK4 links
    for f in ["gtk.css", "gtk-dark.css"]:
        target_link = os.path.join(gtk4_dir, f)
        if is_nix_store_managed(target_link):
            continue
        src_file = ""
        if gtk4_theme_dir and os.path.exists(os.path.join(gtk4_theme_dir, f)):
            src_file = os.path.join(gtk4_theme_dir, f)
        elif gtk3_theme_dir and os.path.exists(os.path.join(gtk3_theme_dir, "libadwaita.css")):
            src_file = os.path.join(gtk3_theme_dir, "libadwaita.css")
        elif gtk3_theme_dir and os.path.exists(os.path.join(gtk3_theme_dir, f)):
            src_file = os.path.join(gtk3_theme_dir, f)

        if os.path.islink(target_link) or os.path.exists(target_link):
            try:
                os.remove(target_link)
            except Exception:
                pass
        if src_file and os.path.exists(src_file):
            try:
                os.symlink(src_file, target_link)
            except Exception:
                pass

    # 2. Update GTK3 links
    for f in ["assets", "libadwaita.css", "libadwaita-tweaks.css"]:
        target_link = os.path.join(gtk3_dir, f)
        if is_nix_store_managed(target_link):
            continue
        src_file = os.path.join(gtk3_theme_dir, f) if (gtk3_theme_dir and os.path.exists(os.path.join(gtk3_theme_dir, f))) else ""
        if os.path.islink(target_link) or os.path.exists(target_link):
            try:
                if os.path.islink(target_link):
                    os.remove(target_link)
                elif os.path.isdir(target_link):
                    shutil.rmtree(target_link)
                else:
                    os.remove(target_link)
            except Exception:
                pass
        if src_file and os.path.exists(src_file):
            try:
                os.symlink(src_file, target_link)
            except Exception:
                pass

def set_gtk_theme(name):
    set_gsettings("org.gnome.desktop.interface", "gtk-theme", name)
    for p in [os.path.join(HOME, ".config/gtk-3.0/settings.ini"), os.path.join(HOME, ".config/gtk-4.0/settings.ini")]:
        update_gtk_ini(p, {"gtk-theme-name": name})
    update_gtk2({"gtk-theme-name": name})
    update_xsettingsd({"Net/ThemeName": name})
    apply_gtk_theme_links(name)
    return {"status": "ok", "gtk_theme": name}

def set_icon_theme(name):
    set_gsettings("org.gnome.desktop.interface", "icon-theme", name)
    for p in [os.path.join(HOME, ".config/gtk-3.0/settings.ini"), os.path.join(HOME, ".config/gtk-4.0/settings.ini")]:
        update_gtk_ini(p, {"gtk-icon-theme-name": name})
    update_gtk2({"gtk-icon-theme-name": name})
    update_xsettingsd({"Net/IconThemeName": name})
    apply_icon_theme_links(name)
    update_default_icon_theme(name)
    build_and_save_icon_cache(name)
    return {"status": "ok", "icon_theme": name}

def set_cursor(name, size):
    try:
        sz = int(size)
    except Exception:
        sz = 24
    set_gsettings("org.gnome.desktop.interface", "cursor-theme", name)
    set_gsettings("org.gnome.desktop.interface", "cursor-size", sz)
    run_proc(["hyprctl", "setcursor", name, str(sz)], timeout=1.0)
    for p in [os.path.join(HOME, ".config/gtk-3.0/settings.ini"), os.path.join(HOME, ".config/gtk-4.0/settings.ini")]:
        update_gtk_ini(p, {
            "gtk-cursor-theme-name": name,
            "gtk-cursor-theme-size": str(sz)
        })
    update_gtk2({
        "gtk-cursor-theme-name": name,
        "gtk-cursor-theme-size": str(sz)
    })
    update_xsettingsd({
        "Gtk/CursorThemeName": name,
        "Gtk/CursorThemeSize": sz
    })
    apply_icon_theme_links(name)
    update_default_icon_theme("", name)
    return {"status": "ok", "cursor_theme": name, "cursor_size": sz}

def set_color_scheme(scheme):
    if scheme in ["true", "True", True]:
        scheme = "prefer-dark"
    elif scheme in ["false", "False", False]:
        scheme = "prefer-light"
        
    is_dark = "1" if scheme == "prefer-dark" else "0"
    set_gsettings("org.gnome.desktop.interface", "color-scheme", scheme)
    
    for p in [os.path.join(HOME, ".config/gtk-3.0/settings.ini"), os.path.join(HOME, ".config/gtk-4.0/settings.ini")]:
        update_gtk_ini(p, {"gtk-application-prefer-dark-theme": is_dark})
        
    return {"status": "ok", "color_scheme": scheme}

def set_font(kind, font_spec):
    schema = "org.gnome.desktop.interface"
    if kind == "interface":
        set_gsettings(schema, "font-name", font_spec)
        for p in [os.path.join(HOME, ".config/gtk-3.0/settings.ini"), os.path.join(HOME, ".config/gtk-4.0/settings.ini")]:
            update_gtk_ini(p, {"gtk-font-name": font_spec})
        update_xsettingsd({"Gtk/FontName": font_spec})
    elif kind == "document":
        set_gsettings(schema, "document-font-name", font_spec)
    elif kind == "monospace":
        set_gsettings(schema, "monospace-font-name", font_spec)
    return {"status": "ok", "kind": kind, "font": font_spec}

def set_font_rendering(hinting, antialiasing, scaling):
    schema = "org.gnome.desktop.interface"
    xsettings_updates = {}
    if hinting:
        set_gsettings(schema, "font-hinting", hinting)
        hint_style = f"hint{hinting}" if hinting in ["none", "slight", "medium", "full"] else "hintslight"
        update_gtk_ini(os.path.join(HOME, ".config/gtk-3.0/settings.ini"), {
            "gtk-xft-hinting": "0" if hinting == "none" else "1",
            "gtk-xft-hintstyle": hint_style
        })
        xsettings_updates["Xft/Hinting"] = 0 if hinting == "none" else 1
        xsettings_updates["Xft/HintStyle"] = hint_style
    if antialiasing:
        set_gsettings(schema, "font-antialiasing", antialiasing)
        rgba_mode = "rgb" if antialiasing == "rgba" else "none"
        update_gtk_ini(os.path.join(HOME, ".config/gtk-3.0/settings.ini"), {
            "gtk-xft-antialias": "0" if antialiasing == "none" else "1",
            "gtk-xft-rgba": rgba_mode
        })
        xsettings_updates["Xft/Antialias"] = 0 if antialiasing == "none" else 1
        xsettings_updates["Xft/RGBA"] = rgba_mode
    if scaling:
        try:
            sc = float(scaling)
            set_gsettings(schema, "text-scaling-factor", sc)
        except Exception:
            pass
    if xsettings_updates:
        update_xsettingsd(xsettings_updates)
    return {"status": "ok", "hinting": hinting, "antialiasing": antialiasing, "scaling": scaling}

def main():
    if len(sys.argv) < 2 or sys.argv[1] == "query":
        res = query_all()
        print(json.dumps(res, indent=2))
        return

    cmd = sys.argv[1]
    if cmd == "set_gtk_theme" and len(sys.argv) >= 3:
        res = set_gtk_theme(sys.argv[2])
        print(json.dumps(res))
    elif cmd == "set_icon_theme" and len(sys.argv) >= 3:
        res = set_icon_theme(sys.argv[2])
        print(json.dumps(res))
    elif cmd == "set_cursor" and len(sys.argv) >= 4:
        res = set_cursor(sys.argv[2], sys.argv[3])
        print(json.dumps(res))
    elif cmd == "set_color_scheme" and len(sys.argv) >= 3:
        res = set_color_scheme(sys.argv[2])
        print(json.dumps(res))
    elif cmd == "set_font" and len(sys.argv) >= 4:
        res = set_font(sys.argv[2], " ".join(sys.argv[3:]))
        print(json.dumps(res))
    elif cmd == "set_font_rendering" and len(sys.argv) >= 5:
        res = set_font_rendering(sys.argv[2], sys.argv[3], sys.argv[4])
        print(json.dumps(res))
    else:
        print(json.dumps({"error": f"Unknown command: {cmd}"}))

if __name__ == "__main__":
    main()

