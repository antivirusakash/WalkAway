from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs" / "app-store-screenshots"
W, H = 1440, 900

FONT = "/System/Library/Fonts/SFNS.ttf"
FONT_ROUNDED = "/System/Library/Fonts/SFNSRounded.ttf"
FONT_MONO = "/System/Library/Fonts/SFNSMono.ttf"


def font(size, mono=False):
    return ImageFont.truetype(FONT_MONO if mono else FONT, size)


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0], size[1]), radius, fill=255)
    return mask


def paste_rounded(dst, src, xy, radius):
    dst.paste(src, xy, rounded_mask(src.size, radius))


def shadow(canvas, box, radius=28, blur=28, offset=(0, 18), alpha=85):
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle(box, radius, fill=(0, 0, 0, alpha))
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(layer, offset)


def gradient(bg_top, bg_bottom):
    img = Image.new("RGBA", (W, H))
    pix = img.load()
    for y in range(H):
        t = y / (H - 1)
        col = tuple(int(bg_top[i] * (1 - t) + bg_bottom[i] * t) for i in range(3))
        for x in range(W):
            pix[x, y] = (*col, 255)
    return img


def icon(size):
    src = Image.open(ROOT / "Resources" / "WalkAway-icon-preview.png").convert("RGBA")
    src.thumbnail((size, size), Image.Resampling.LANCZOS)
    bg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bg.alpha_composite(src, ((size - src.width) // 2, (size - src.height) // 2))
    return bg


def draw_text(draw, xy, text, fnt, fill, max_width=None, line_gap=8):
    if not max_width:
        draw.text(xy, text, font=fnt, fill=fill)
        return xy[1] + draw.textbbox(xy, text, font=fnt)[3] - xy[1]

    words = text.split()
    lines, line = [], ""
    for word in words:
        candidate = word if not line else f"{line} {word}"
        if draw.textlength(candidate, font=fnt) <= max_width:
            line = candidate
        else:
            if line:
                lines.append(line)
            line = word
    if line:
        lines.append(line)

    y = xy[1]
    for line in lines:
        draw.text((xy[0], y), line, font=fnt, fill=fill)
        y += fnt.size + line_gap
    return y


def menu_bar(draw, y=84, active=True):
    draw.rounded_rectangle((170, y, 1270, y + 42), 14, fill=(247, 249, 252, 235))
    draw.text((198, y + 11), "Finder", font=font(14), fill=(32, 40, 48))
    for i, item in enumerate(["File", "Edit", "View", "Window", "Help"]):
        draw.text((260 + i * 70, y + 11), item, font=font(14), fill=(72, 82, 93))
    x = 1030
    draw.ellipse((x, y + 14, x + 12, y + 26), fill=(39, 174, 96) if active else (132, 144, 156))
    draw.text((x + 20, y + 11), "WalkAway -47", font=font(14), fill=(35, 45, 55))
    draw.text((1178, y + 11), "9:41 AM", font=font(14), fill=(72, 82, 93))


def desktop(canvas, title, subtitle, accent=(22, 163, 74), dark=False):
    draw = ImageDraw.Draw(canvas)
    menu_bar(draw, active=accent == (22, 163, 74))
    canvas.alpha_composite(icon(70), (180, 176))
    title_bottom = draw_text(draw, (270, 166), title, font(44), (18, 28, 38), max_width=465, line_gap=4)
    draw_text(draw, (272, title_bottom + 14), subtitle, font(21), (66, 77, 88), max_width=470, line_gap=7)
    return draw


def slider(draw, x, y, width, value, fill=(46, 124, 246), knob=(255, 255, 255)):
    draw.rounded_rectangle((x, y, x + width, y + 5), 3, fill=(213, 219, 227))
    draw.rounded_rectangle((x, y, x + int(width * value), y + 5), 3, fill=fill)
    kx = x + int(width * value)
    draw.ellipse((kx - 9, y - 7, kx + 9, y + 11), fill=knob, outline=(166, 175, 186), width=1)


def toggle(draw, x, y, on=True):
    fill = (35, 174, 96) if on else (180, 188, 198)
    draw.rounded_rectangle((x, y, x + 38, y + 22), 11, fill=fill)
    cx = x + (26 if on else 12)
    draw.ellipse((cx - 8, y + 3, cx + 8, y + 19), fill=(255, 255, 255))


def panel(state="nearby", advanced=False, diagnostics=False, width=360):
    height = 560 if advanced else 488
    if diagnostics:
        height = 540
    img = Image.new("RGBA", (width, height), (250, 251, 253, 252))
    d = ImageDraw.Draw(img)
    pad = 22

    status = {
        "nearby": ("Nearby", "Akash's Apple Watch - 1.2 m - -47 dBm", (22, 163, 74)),
        "leaving": ("Leaving", "Locking in 5 s", (226, 130, 36)),
        "locked": ("Locked", "Mac locked for this absence", (22, 163, 74)),
        "missing": ("No watch selected", "Scanning for nearby BLE devices", (118, 128, 139)),
    }[state]

    d.ellipse((pad, pad + 4, pad + 38, pad + 42), fill=status[2])
    d.rounded_rectangle((pad + 11, pad + 16, pad + 28, pad + 32), 4, outline=(255, 255, 255), width=3)
    d.arc((pad + 15, pad + 8, pad + 25, pad + 22), 180, 360, fill=(255, 255, 255), width=3)
    d.text((pad + 54, pad + 3), status[0], font=font(22), fill=status[2])
    d.text((pad + 54, pad + 31), status[1], font=font(13), fill=(94, 104, 116))
    y = 84
    d.line((pad, y, width - pad, y), fill=(221, 226, 232))
    y += 18

    d.text((pad, y), "Apple Watch", font=font(16), fill=(26, 34, 43))
    d.text((pad, y + 24), "Connected", font=font(13), fill=(93, 104, 117))
    d.rounded_rectangle((width - pad - 72, y - 2, width - pad, y + 26), 8, fill=(238, 242, 247), outline=(210, 218, 228))
    d.text((width - pad - 55, y + 4), "Rescan", font=font(13), fill=(43, 92, 171))
    y += 70
    d.line((pad, y, width - pad, y), fill=(221, 226, 232))
    y += 18

    d.text((pad, y), "Lock by distance", font=font(15), fill=(29, 38, 48))
    toggle(d, width - pad - 38, y - 1, True)
    y += 48
    d.text((pad, y), "Distance", font=font(13), fill=(84, 96, 110))
    d.text((width - pad - 36, y), "6 m", font=font(13, mono=True), fill=(84, 96, 110))
    slider(d, pad, y + 26, width - pad * 2, 0.24)
    y += 64
    d.text((pad, y), "Current", font=font(13), fill=(84, 96, 110))
    d.text((width - pad - 46, y), "1.2 m", font=font(13, mono=True), fill=(84, 96, 110))
    y += 38
    d.text((pad, y), "Lock delay", font=font(13), fill=(84, 96, 110))
    d.text((width - pad - 34, y), "5 s", font=font(13, mono=True), fill=(84, 96, 110))
    slider(d, pad, y + 26, width - pad * 2, 0.14)
    y += 64
    d.text((pad, y), "Pause while active", font=font(15), fill=(29, 38, 48))
    toggle(d, width - pad - 38, y - 1, True)
    y += 50

    if advanced:
        d.text((pad, y), "Advanced", font=font(14), fill=(41, 51, 62))
        y += 30
        for label, value in [("Missing signal", "12 s"), ("Lock when signal is lost", "On"), ("Launch at login", "On")]:
            d.text((pad, y), label, font=font(12), fill=(88, 99, 112))
            d.text((width - pad - d.textlength(value, font=font(12, mono=True)), y), value, font=font(12, mono=True), fill=(88, 99, 112))
            y += 30

    if diagnostics:
        d.text((pad, y), "Diagnostics", font=font(14), fill=(41, 51, 62))
        y += 30
        for label, value in [("Memory", "42 MB"), ("CPU (app)", "0.18 %"), ("Poll cost", "38 ms avg"), ("Locks", "4"), ("Away events", "9")]:
            d.text((pad, y), label, font=font(12), fill=(88, 99, 112))
            d.text((width - pad - d.textlength(value, font=font(12, mono=True)), y), value, font=font(12, mono=True), fill=(88, 99, 112))
            y += 27

    d.line((pad, height - 58, width - pad, height - 58), fill=(221, 226, 232))
    d.rounded_rectangle((pad, height - 38, pad + 100, height - 12), 8, fill=(238, 242, 247), outline=(210, 218, 228))
    d.text((pad + 18, height - 33), "Lock Now", font=font(13), fill=(28, 40, 52))
    d.text((width - pad - 36, height - 33), "Quit", font=font(13), fill=(178, 54, 54))
    return img


def mac_window(content, x, y, title="WalkAway"):
    w, h = content.size
    frame = Image.new("RGBA", (w + 28, h + 72), (0, 0, 0, 0))
    d = ImageDraw.Draw(frame)
    d.rounded_rectangle((0, 0, w + 28, h + 72), 18, fill=(244, 247, 250), outline=(202, 211, 222))
    d.rounded_rectangle((0, 0, w + 28, 50), 18, fill=(235, 240, 246), outline=(202, 211, 222))
    for i, col in enumerate([(255, 95, 86), (255, 189, 46), (39, 201, 63)]):
        d.ellipse((18 + i * 22, 18, 30 + i * 22, 30), fill=col)
    d.text(((w + 28 - d.textlength(title, font=font(13))) / 2, 16), title, font=font(13), fill=(85, 96, 109))
    paste_rounded(frame, content, (14, 58), 14)
    return frame


def draw_status_strip(draw, x, y, width, items):
    for label, value, col in items:
        box_w = width // len(items) - 16
        draw.rounded_rectangle((x, y, x + box_w, y + 84), 14, fill=(255, 255, 255, 232), outline=(215, 222, 231))
        draw.text((x + 22, y + 18), label, font=font(13), fill=(95, 107, 120))
        draw.text((x + 22, y + 42), value, font=font(24), fill=col)
        x += box_w + 24


def make_slide(idx, title, subtitle, state="nearby", advanced=False, diagnostics=False, accent=(22, 163, 74)):
    canvas = gradient((229, 238, 247), (250, 252, 253))
    draw = desktop(canvas, title, subtitle, accent=accent)

    if idx == 1:
        content = panel(state="nearby", width=380)
        frame = mac_window(content, 0, 0, "Menu Bar")
        shadow(canvas, (760, 170, 760 + frame.width, 170 + frame.height), 24, 24, (0, 14), 80)
        canvas.alpha_composite(frame, (760, 170))
        draw_status_strip(draw, 190, 610, 500, [("Presence", "1.2 m", (22, 163, 74)), ("Signal", "-47 dBm", (46, 124, 246))])
    elif idx == 2:
        content = panel(state="leaving", width=380)
        frame = mac_window(content, 0, 0, "Settings")
        shadow(canvas, (745, 158, 745 + frame.width, 158 + frame.height), 24, 24, (0, 14), 80)
        canvas.alpha_composite(frame, (745, 158))
        draw_status_strip(draw, 190, 610, 500, [("Away point", "6 m", (46, 124, 246)), ("Grace", "5 s", (226, 130, 36))])
    elif idx == 3:
        content = panel(state="nearby", width=380)
        frame = mac_window(content, 0, 0, "Active Mac")
        shadow(canvas, (745, 158, 745 + frame.width, 158 + frame.height), 24, 24, (0, 14), 80)
        canvas.alpha_composite(frame, (745, 158))
        d = ImageDraw.Draw(canvas)
        d.rounded_rectangle((198, 610, 650, 746), 18, fill=(255, 255, 255, 232), outline=(215, 222, 231))
        d.text((226, 636), "Typing or moving the mouse?", font=font(18), fill=(30, 40, 50))
        d.text((226, 672), "WalkAway waits until you are truly gone.", font=font(22), fill=(22, 163, 74))
    elif idx == 4:
        content = panel(state="nearby", advanced=True, width=380)
        frame = mac_window(content, 0, 0, "Privacy")
        shadow(canvas, (745, 130, 745 + frame.width, 130 + frame.height), 24, 24, (0, 14), 80)
        canvas.alpha_composite(frame, (745, 130))
        for i, (label, desc) in enumerate([("No account", "Nothing to sign into"), ("No cloud", "Data stays on your Mac"), ("No tracking", "Only the watch you choose")]):
            y = 600 + i * 54
            draw.ellipse((202, y + 5, 222, y + 25), fill=(22, 163, 74))
            draw.text((240, y), label, font=font(18), fill=(30, 40, 50))
            draw.text((240, y + 26), desc, font=font(14), fill=(92, 104, 118))
    elif idx == 5:
        content = panel(state="nearby", diagnostics=True, width=380)
        frame = mac_window(content, 0, 0, "Diagnostics")
        shadow(canvas, (745, 146, 745 + frame.width, 146 + frame.height), 24, 24, (0, 14), 80)
        canvas.alpha_composite(frame, (745, 146))
        draw_status_strip(draw, 190, 610, 500, [("Memory", "42 MB", (46, 124, 246)), ("CPU", "0.18 %", (22, 163, 74))])

    out = OUT / f"{idx:02d}-{slug(title)}.png"
    canvas.convert("RGB").save(out, quality=95)
    return out


def slug(text):
    return "".join(c.lower() if c.isalnum() else "-" for c in text).strip("-").replace("--", "-")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    slides = [
        ("Lock your Mac when you leave", "WalkAway lives in the menu bar and locks on presence, not idle time.", "nearby", False, False, (22, 163, 74)),
        ("Set the distance that feels right", "Choose how far is away, then let the short grace period handle the lock.", "leaving", False, False, (226, 130, 36)),
        ("Keeps working while you do", "Pause while active prevents mid-sentence locks while you type, read, or use the mouse.", "nearby", False, False, (22, 163, 74)),
        ("Private by design", "No account, no cloud, no tracking. Bluetooth signal checks stay on your Mac.", "nearby", True, False, (22, 163, 74)),
        ("Quiet tools when you need them", "Diagnostics, launch at login, calibration, and manual Lock Now stay one click away.", "nearby", False, True, (46, 124, 246)),
    ]
    paths = []
    for i, slide in enumerate(slides, start=1):
        paths.append(make_slide(i, *slide))

    test = OUT / "test-main-window.png"
    Image.open(paths[0]).save(test)
    print("\n".join(str(p) for p in paths + [test]))


if __name__ == "__main__":
    main()
