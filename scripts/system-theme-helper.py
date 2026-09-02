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
    Follows deep symlink chains to detect indirect Home Manager links.
    Guarantees that nix store files, profiles, and home-manager-files links are never modified.
    """
    try:
        if not os.path.exists(path) and not os.path.islink(path):
            return False
        # If the parent directory itself is in a read-only system or nix path
        parent_real = os.path.realpath(os.path.dirname(path))
        if parent_real.startswith("/nix/store") or parent_real.startswith("/run/current-system") or parent_real.startswith("/etc/profiles"):
            return True
        # Follow symlink chains (up to 8 levels) to detect indirect Home Manager links
        current = path
        for _ in range(8):
            if not os.path.islink(current):
                break
            target = os.readlink(current)
            if not os.path.isabs(target):
                target = os.path.join(os.path.dirname(current), target)
            if "home-manager-files" in target or "/nix/store" in target:
                return True
            current = target
        # Check resolved real path
        real = os.path.realpath(path)
        if "home-manager-files" in real or real.startswith("/nix/store"):
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
    """
    Creates symlinks for icon themes in ~/.icons and ~/.local/share/icons.
    SAFE: only creates missing/broken symlinks. Never unlinks existing valid symlinks.
    This protects NixOS/Home-Manager-managed symlinks from being disrupted.
    """
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

            # If dest already exists and is valid (not broken), leave it alone.
            # This is the key safety rule: we never unlink an existing valid symlink
            # because it may be managed by NixOS or another tool.
            if os.path.exists(dest_link):
                continue

            # Only act on broken symlinks (dangling) or truly absent paths
            if os.path.islink(dest_link):
                # Symlink exists but is broken — safe to replace
                try:
                    os.unlink(dest_link)
                except Exception:
                    pass
            elif os.path.isdir(dest_link) and not os.path.islink(dest_link):
                # Real directory — only remove if empty
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
                if not os.path.isdir(full):
                    continue
                if os.path.isdir(os.path.join(full, "cursors")):
                    cursors.add(d)
                idx = os.path.join(full, "index.theme")
                if os.path.exists(idx):
                    # Check if it has icon directories definition or actual icon subfolders
                    has_dirs = False
                    try:
                        with open(idx, "r", encoding="utf-8", errors="ignore") as f:
                            for line in f:
                                if line.strip().startswith("Directories="):
                                    has_dirs = True
                                    break
                    except Exception:
                        pass
                    sub = os.listdir(full)
                    has_real_icons = has_dirs or any(f in sub for f in [
                        "apps", "apps@2x", "places", "places@2x", "mimes", "mimes@2x",
                        "actions", "actions@2x", "categories", "categories@2x", "scalable",
                        "48x48", "64x64", "128x128", "256x256", "16x16", "22x22", "24x24", "32x32"
                    ])
                    if has_real_icons:
                        icons.add(d)
        except Exception:
            pass
    icon_list = sorted(list(icons))
    cursor_list = sorted(list(cursors))
    if not icon_list:
        icon_list = ["WhiteSur-dark", "WhiteSur", "MacTahoe", "breeze", "hicolor"]
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
    ordered_themes = []
    seen_themes = set()
    search_bases = get_data_dirs("icons")

    def push_theme(tname):
        if not tname or tname in seen_themes:
            return
        seen_themes.add(tname)
        ordered_themes.append(tname)

    push_theme(theme_name)
    # If dark or light variant, push base theme immediately after
    for suffix in ["-dark", "-light", "_dark", "_light", "-Dark", "-Light"]:
        if theme_name.endswith(suffix):
            push_theme(theme_name[:-len(suffix)])
            break

    # Read Inherits from index.theme of theme and base
    for t in list(ordered_themes):
        for base in search_bases:
            idx = os.path.join(base, t, "index.theme")
            if os.path.isfile(idx):
                try:
                    with open(idx, "r", encoding="utf-8", errors="ignore") as f:
                        for line in f:
                            if line.strip().startswith("Inherits="):
                                for inh in line.strip()[9:].split(","):
                                    inh_clean = inh.strip()
                                    if inh_clean and inh_clean.lower() != "hicolor":
                                        push_theme(inh_clean)
                except Exception:
                    pass

    # Common desktop fallbacks
    for fb in ["Adwaita", "breeze", "breeze-dark", "gnome", "Pop", "WhiteSur", "MacTahoe", "Cosmic"]:
        push_theme(fb)
    # Hicolor universal fallback
    push_theme("hicolor")

    # Convert theme names to directory paths
    dirs = []
    seen_dirs = set()
    for t in ordered_themes:
        for base in search_bases:
            tdir = os.path.join(base, t)
            if os.path.isdir(tdir) and tdir not in seen_dirs:
                seen_dirs.add(tdir)
                dirs.append((t, tdir))

    for pix in get_data_dirs("pixmaps"):
        if os.path.isdir(pix) and pix not in seen_dirs:
            seen_dirs.add(pix)
            dirs.append(("pixmaps", pix))

    return dirs

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

    theme_dirs = get_theme_dirs_with_inheritance(theme_name)
    cache = {}
    scores = {}

    total_themes = len(set(t for t, _ in theme_dirs))
    theme_order_map = {}
    idx = 0
    for t, _ in theme_dirs:
        if t not in theme_order_map:
            theme_order_map[t] = idx
            idx += 1

    ext_order = [".svg", ".png", ".xpm"]
    scanned_real_paths = set()

    for theme_tag, p in theme_dirs:
        real_p = os.path.realpath(p)
        if real_p in scanned_real_paths:
            continue
        scanned_real_paths.add(real_p)

        t_idx = theme_order_map.get(theme_tag, 99)
        dir_weight = max(1000, (total_themes - t_idx) * 10000)

        for root, dirs, files in os.walk(p):
            for f in files:
                name, ext = os.path.splitext(f)
                ext = ext.lower()
                if ext not in ext_order:
                    continue

                full_path = os.path.join(root, f)
                p_low = full_path.lower()
                is_file_symbolic = "symbolic" in p_low or name.lower().endswith("-symbolic") or name.lower().endswith("_symbolic")

                cat_score = 0
                if "/apps/" in p_low or "/apps@2x/" in p_low or "/applications/" in p_low:
                    cat_score += 15000
                elif "/categories/" in p_low or "/categories@2x/" in p_low:
                    cat_score += 10000
                elif "/devices/" in p_low or "/places/" in p_low:
                    cat_score += 8000
                elif "/preferences/" in p_low:
                    cat_score += 6000
                elif "/actions/" in p_low:
                    cat_score += 4000
                elif "/status/" in p_low:
                    cat_score += 2000

                size_score = 0
                if "scalable" in p_low or ext == ".svg":
                    size_score += 4000
                elif any(s in p_low for s in ["512", "256", "128", "96", "64", "48"]):
                    size_score += 3000
                elif any(s in p_low for s in ["32", "24", "22"]):
                    size_score += 1500
                elif "16" in p_low:
                    size_score += 500

                base_score = dir_weight + cat_score + size_score
                name_low = name.lower()

                # List of (key, score)
                entries = []
                # 1. Exact name
                exact_score = base_score if (not is_file_symbolic or "symbolic" in name_low) else (base_score - 80000)
                entries.append((name_low, exact_score))

                # 2. If symbolic, also provide stripped fallback with severe penalty
                if is_file_symbolic:
                    clean_sym = name_low.replace("-symbolic", "").replace("_symbolic", "")
                    if clean_sym != name_low:
                        entries.append((clean_sym, base_score - 80000))

                # 3. Dotted / Reverse-DNS aliases
                if "." in name_low:
                    parts = name_low.split(".")
                    last_part = parts[-1]
                    clean_last = last_part.replace("-symbolic", "").replace("_symbolic", "")
                    alias_pen = 80000 if is_file_symbolic else 0
                    entries.append((clean_last, base_score - 500 - alias_pen))
                    entries.append((name_low.replace(".", "-"), base_score - 200 - alias_pen))
                    if name_low.startswith("org.gnome."):
                        entries.append(("gnome-" + name_low[10:].replace("-symbolic", ""), base_score - 300 - alias_pen))
                    if name_low.startswith("org.kde."):
                        entries.append((name_low[8:].replace("-symbolic", ""), base_score - 300 - alias_pen))
                    if name_low.startswith("com.system76."):
                        sys76 = name_low[13:].replace("-symbolic", "")
                        entries.append((sys76, base_score - 300 - alias_pen))
                        if sys76.startswith("cosmic") and len(sys76) > 6:
                            entries.append(("cosmic-" + sys76[6:], base_score - 300 - alias_pen))
                    if len(parts) >= 2:
                        entries.append((parts[-2], base_score - 800 - alias_pen))

                for k, sc in entries:
                    if k and (k not in cache or sc > scores.get(k, -999999)):
                        cache[k] = full_path
                        scores[k] = sc
                            
    priority_aliases = {
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
    for alias_k, target_k in priority_aliases.items():
        if target_k.startswith("/"):
            if os.path.exists(target_k):
                cache[alias_k] = target_k
        elif target_k in cache:
            # If target exists, overwrite or fill alias
            if alias_k not in cache or alias_k in ["settings", "quickshell-settings", "system-settings", "helium", "antigravity-ide"]:
                cache[alias_k] = cache[target_k]
        elif alias_k in cache and not target_k.startswith("/"):
            if target_k not in cache:
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
    ensure_session_portal_ready()
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

    # 1. Update GTK4 links — skip entirely if gtk4_dir itself is nix-managed
    for f in ["gtk.css", "gtk-dark.css"]:
        target_link = os.path.join(gtk4_dir, f)
        if is_nix_store_managed(target_link):
            continue
        # Also skip if the parent settings.ini is nix-managed (whole dir is controlled)
        if is_nix_store_managed(os.path.join(gtk4_dir, "settings.ini")):
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

    # 2. Update GTK3 links — protect any file already managed by NixOS
    for f in ["assets", "libadwaita.css", "libadwaita-tweaks.css"]:
        target_link = os.path.join(gtk3_dir, f)
        if is_nix_store_managed(target_link):
            continue
        # Also skip if gtk-3.0/settings.ini is nix-managed (whole dir is controlled)
        if is_nix_store_managed(os.path.join(gtk3_dir, "settings.ini")):
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
    # NOTE: apply_icon_theme_links is intentionally NOT called here.
    # It is only called during initial setup or explicit link repair,
    # to avoid disrupting NixOS/Home-Manager-managed symlinks in
    # ~/.icons and ~/.local/share/icons on every icon theme switch.
    update_default_icon_theme(name)
    build_and_save_icon_cache(name, force_rebuild=True)
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

def ensure_session_portal_ready():
    """
    Ensures that on NixOS/Hyprland, the session targets and environment
    are exported to systemd/dbus so xdg-desktop-portal services operate properly.
    """
    try:
        run_proc(["systemctl", "--user", "start", "nixos-fake-graphical-session.target"], timeout=1.0)
        run_proc([
            "dbus-update-activation-environment", "--systemd",
            "WAYLAND_DISPLAY", "XDG_CURRENT_DESKTOP", "DISPLAY", "QT_QPA_PLATFORM", "XDG_SESSION_TYPE"
        ], timeout=1.0)
    except Exception:
        pass

def notify_gtk_color_scheme(scheme):
    """
    Broadcasts the color scheme change to all running GTK/libadwaita/Chromium/Electron applications
    via multiple mechanisms for maximum compatibility, especially on NixOS.
    """
    is_dark = scheme == "prefer-dark"

    # 0. Ensure systemd graphical session target & environment are active for XDG portal on NixOS
    ensure_session_portal_ready()

    # 1. gsettings + dconf (most reliable for GNOME/GTK/portal-based apps)
    set_gsettings("org.gnome.desktop.interface", "color-scheme", scheme)

    # 2. XDG Desktop Portal - org.freedesktop.portal.Settings
    # This is the standard Wayland/portal mechanism that Chromium/Helium/Firefox/GTK4/libadwaita apps listen to
    portal_val = "1" if is_dark else "2"  # 1=dark, 2=light (XDG portal spec)
    run_proc([
        "gdbus", "call", "--session",
        "--dest", "org.freedesktop.portal.Desktop",
        "--object-path", "/org/freedesktop/portal/desktop",
        "--method", "org.freedesktop.portal.Settings.ReadOne",
        "org.freedesktop.appearance", "color-scheme"
    ], timeout=1.0)  # activates portal if dormant

    # Emit the change signal via gdbus and dbus-send for portals that listen
    run_proc([
        "gdbus", "emit", "--session",
        "--path", "/org/freedesktop/portal/desktop",
        "--interface", "org.freedesktop.portal.Settings",
        "--signal", "SettingChanged",
        "org.freedesktop.appearance", "color-scheme", f"<uint32 {portal_val}>"
    ], timeout=1.0)

    run_proc([
        "dbus-send", "--session", "--type=signal",
        "/org/freedesktop/portal/desktop",
        "org.freedesktop.portal.Settings.SettingChanged",
        "string:org.freedesktop.appearance",
        "string:color-scheme",
        f"variant:uint32:{portal_val}"
    ], timeout=1.0)

    # 3. Notify via GNOME Shell D-Bus if available (for running shell extensions)
    run_proc([
        "gdbus", "call", "--session",
        "--dest", "org.gnome.Shell",
        "--object-path", "/org/gnome/Shell",
        "--method", "org.gnome.Shell.Eval",
        "global.reloadTheme ? global.reloadTheme() : null"
    ], timeout=0.5)

    # 4. Notify xsettingsd if present (forces X11 / GTK2/3 clients to update)
    run_proc(["pkill", "-HUP", "xsettingsd"], timeout=0.5)


def set_color_scheme(scheme):
    if scheme in ["true", "True", True]:
        scheme = "prefer-dark"
    elif scheme in ["false", "False", False]:
        scheme = "prefer-light"

    is_dark = "1" if scheme == "prefer-dark" else "0"

    # Apply to GTK ini files - for NixOS, write to override dirs if primary is managed
    for gtk_ver in ["gtk-3.0", "gtk-4.0"]:
        primary_path = os.path.join(HOME, f".config/{gtk_ver}/settings.ini")
        if is_nix_store_managed(primary_path):
            # On NixOS, write a separate override config that GTK picks up
            # GTK looks for settings in multiple locations; write to per-user override
            override_dir = os.path.join(HOME, f".config/{gtk_ver}")
            os.makedirs(override_dir, exist_ok=True)
            override_path = os.path.join(override_dir, "qs-theme-override.ini")
            try:
                with open(override_path, "w", encoding="utf-8") as f:
                    f.write(f"[Settings]\ngtk-application-prefer-dark-theme={is_dark}\n")
            except Exception:
                pass
        else:
            update_gtk_ini(primary_path, {"gtk-application-prefer-dark-theme": is_dark})

    # Broadcast change to all running apps
    notify_gtk_color_scheme(scheme)

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

