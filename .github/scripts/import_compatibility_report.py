#!/usr/bin/env python3
import os
import re
import sys

OTHER_OPTION_LABEL = "Other (Please specify and follow our naming convention)"

FEATURE_MAP = [
    ("Main Camera (Photo)", "Main Camera"),
    ("Ultrawide Camera", "Ultrawide"),
    ("Macro Camera", "Macro"),
    ("Telephoto Camera", "Telephoto"),
    ("Front (Selfie) Camera", "Front Selfie"),
    ("Ultra-Res Photo Mode (High-Resolution)", "Ultra-Res"),
    ("Video Recording (1080p / 4K)", "Video 4K"),
    ("Slow Motion Video", "Slow Motion"),
    ("Portrait Mode", "Portrait"),
    ("Pro / Manual Mode", "Pro"),
]

def clean_cell(text: str) -> str:
    """Sanitize text for markdown table cells."""
    if not text or text.strip() in ("_No response_", "None", "n/a", "N/A"):
        return "—"
    cleaned = text.strip().replace("\r", "").replace("\n", " ")
    cleaned = cleaned.replace("|", "\\|")
    return cleaned

def parse_compiler_method(method_raw: str) -> str:
    method_clean = clean_cell(method_raw)
    if ".sh" in method_clean:
        return "`.sh`"
    elif ".ps1" in method_clean:
        return "`.ps1`"
    elif ".bat" in method_clean:
        return "`.bat`"
    return method_clean

def parse_issue_form(body: str) -> dict:
    """Parse GitHub Issue Form markdown body into key-value pairs."""
    fields = {}
    current_key = None
    current_lines = []

    for line in body.splitlines():
        if line.startswith("### "):
            if current_key:
                fields[current_key] = "\n".join(current_lines).strip()
            current_key = line[4:].strip()
            current_lines = []
        else:
            if current_key:
                current_lines.append(line)

    if current_key:
        fields[current_key] = "\n".join(current_lines).strip()

    return fields

def parse_sensor_summary(fields: dict) -> str:
    """Extract working and failing sensors into a clean one-line summary."""
    working = []
    not_working = []

    has_dropdown = any(key in fields for key, _ in FEATURE_MAP)

    if has_dropdown:
        for field_key, short_name in FEATURE_MAP:
            val = fields.get(field_key, "").strip().lower()
            if "not working" in val:
                not_working.append(short_name)
            elif "working" in val:
                working.append(short_name)
    else:
        breakdown_raw = fields.get("Sensor & Feature Breakdown", "")
        if not breakdown_raw or breakdown_raw.strip() in ("_No response_", "None", "n/a", "N/A"):
            return "—"
        for line in breakdown_raw.splitlines():
            line_clean = line.strip()
            if not line_clean.startswith("- "):
                continue
            parts = line_clean[2:].split(":", 1)
            if len(parts) != 2:
                continue
            feat_name = parts[0].strip()
            feat_name = feat_name.replace(" (Photo)", "").replace(" (Selfie) Camera", " Selfie").replace(" Recording (1080p / 4K)", " 4K").replace(" Mode", "").replace(" Photo Mode (High-Resolution)", "")
            status = parts[1].strip().lower()
            if "not working" in status:
                not_working.append(feat_name)
            elif "working" in status:
                working.append(feat_name)

    parts_summary = []
    if working:
        parts_summary.append("Working: " + ", ".join(working))
    if not_working:
        parts_summary.append("Fails: " + ", ".join(not_working))

    if not parts_summary:
        return "—"
    return "; ".join(parts_summary)

def determine_badge(result_text: str) -> tuple[str, str]:
    """Return badge emoji and standardized result category."""
    res = result_text.lower()
    if "works perfectly" in res:
        return "🟢", "Works Perfectly"
    elif "mostly working" in res:
        return "🟡", "Mostly Working"
    elif "app crashes" in res:
        return "🔴", "App Crashes"
    elif "app missing" in res:
        return "⚪", "App Missing"
    elif "won't boot" in res or "wont boot" in res:
        return "⛔", "Won't Boot"
    elif "won't compile" in res or "wont compile" in res or "compile fail" in res:
        return "⚠️", "Won't Compile"
    elif "untested" in res:
        return "❔", "Untested"
    return "⚪", clean_cell(result_text)

def extract_row_link_name(cell: str) -> str:
    """Extract plain device name from markdown table cell like [**name**](reports/x.md)."""
    m = re.search(r"\[(?:\*\*)?(.*?)(?:\*\*)?\]\(", cell)
    return m.group(1).strip() if m else cell.strip()

def update_compatibility_md(
    device_name: str,
    codename: str,
    custom_rom: str,
    camera_gen: str,
    badge_emoji: str,
    result_cat: str,
    compat_file: str = "COMPATIBILITY.md",
):
    """Update Status column for codename in COMPATIBILITY.md, or insert new Community device entry."""
    if not os.path.exists(compat_file):
        print(f"[WARN] {compat_file} does not exist.")
        return

    with open(compat_file, "r", encoding="utf-8") as f:
        content = f.read()

    lines = content.splitlines(keepends=True)
    target_pattern = f"reports/{codename}.md"
    target_badge_str = f" {badge_emoji} {result_cat} "

    updated_lines = []
    updated_count = 0
    exact_variant_found = False
    in_community_section = False

    for line in lines:
        stripped = line.strip()
        if stripped.startswith("## "):
            in_community_section = "Community / Unofficial ROM Devices" in stripped

        if target_pattern in line and stripped.startswith("|") and stripped.endswith("|"):
            parts = line.split("|")
            if len(parts) >= 6:
                row_dev_name = extract_row_link_name(parts[1])
                if row_dev_name.lower() == device_name.lower():
                    exact_variant_found = True
                    if in_community_section and custom_rom and custom_rom != "—":
                        parts[3] = f" {custom_rom} "
                    if in_community_section and camera_gen and camera_gen != "—":
                        parts[4] = f" {camera_gen} "
                parts[5] = target_badge_str
                newline = "\n" if line.endswith("\n") else ""
                line = "|".join(parts)
                if newline and not line.endswith("\n"):
                    line += newline
                updated_count += 1
        updated_lines.append(line)

    new_content = "".join(updated_lines)

    # If this (device_name, codename) is not listed anywhere in COMPATIBILITY.md, add to Community section
    if not exact_variant_found:
        rom_col = custom_rom if custom_rom and custom_rom != "—" else "Unofficial / Custom ROM"
        era_col = camera_gen if camera_gen and camera_gen != "—" else "—"
        new_comm_row = f"| [**{device_name}**](reports/{codename}.md) | `{codename}` | {rom_col} | {era_col} | {badge_emoji} {result_cat} |"

        comm_section_pattern = re.compile(
            r"(## 🌐 Community / Unofficial ROM Devices \(\d+\)\n+.*?\n+\| Device Name \| Codename \| Reported Custom ROM \| Stock Camera Era \| Status \|\n\| :--- \| :--- \| :--- \| :--- \| :---: \|\n)((?:\|[^\n]*\n)*)",
            re.DOTALL,
        )
        m_comm = comm_section_pattern.search(new_content)
        if m_comm:
            existing_rows_block = m_comm.group(2)
            comm_rows = []
            for rline in existing_rows_block.splitlines():
                rstrip = rline.strip()
                if not rstrip.startswith("|") or "*no community-added devices yet*" in rstrip.lower():
                    continue
                comm_rows.append(rstrip)
            comm_rows.append(new_comm_row)
            comm_rows.sort(key=lambda r: extract_row_link_name(r.split("|")[1]).lower())

            new_header = re.sub(
                r"## 🌐 Community / Unofficial ROM Devices \(\d+\)",
                f"## 🌐 Community / Unofficial ROM Devices ({len(comm_rows)})",
                m_comm.group(1),
            )
            replacement_block = new_header + "\n".join(comm_rows) + "\n"
            new_content = new_content[:m_comm.start()] + replacement_block + new_content[m_comm.end():]
        else:
            # Fallback: insert Community section right before Legacy section
            comm_section = (
                "## 🌐 Community / Unofficial ROM Devices (1)\n\n"
                "Motorola devices without official LineageOS Wiki entries (or regional variants) reported by the community on unofficial LineageOS builds or other custom ROMs. "
                "Select **Other** in the [Compatibility Report Form](https://github.com/vrwindsor1/Moto-Camera-Restored/issues/new?template=compatibility_report.yml) to add a device here.\n\n"
                "| Device Name | Codename | Reported Custom ROM | Stock Camera Era | Status |\n"
                "| :--- | :--- | :--- | :--- | :---: |\n"
                f"{new_comm_row}\n\n---\n\n"
            )
            if "## 🏛️ Legacy / Discontinued Motorola Devices" in new_content:
                new_content = new_content.replace(
                    "## 🏛️ Legacy / Discontinued Motorola Devices",
                    comm_section + "## 🏛️ Legacy / Discontinued Motorola Devices",
                    1,
                )
            else:
                new_content += "\n---\n\n" + comm_section

        # Update top summary line counts if present
        m_active = re.search(r"## 📱 Actively Maintained Motorola Devices \((\d+)\)", new_content)
        m_comm_cnt = re.search(r"## 🌐 Community / Unofficial ROM Devices \((\d+)\)", new_content)
        m_legacy = re.search(r"## 🏛️ Legacy / Discontinued Motorola Devices \((\d+)\)", new_content)
        if m_active and m_comm_cnt and m_legacy:
            a_cnt = int(m_active.group(1))
            c_cnt = int(m_comm_cnt.group(1))
            l_cnt = int(m_legacy.group(1))
            total_cnt = a_cnt + c_cnt + l_cnt
            new_content = re.sub(
                r"> \*\*Total Motorola Devices Tracked:\*\* `[^`]+` \([^\n]+\)",
                f"> **Total Motorola Devices Tracked:** `{total_cnt}` (`{a_cnt}` actively maintained, `{c_cnt}` community / unofficial, `{l_cnt}` discontinued)",
                new_content,
            )
        print(f"[INFO] Added new Community device entry '{device_name} ({codename})' to {compat_file}.")
    else:
        print(f"[INFO] Updated {updated_count} row(s) in {compat_file} for '{device_name} ({codename})' to {badge_emoji} {result_cat}.")

    with open(compat_file, "w", encoding="utf-8") as f:
        f.write(new_content)

def ensure_device_in_issue_template(
    device_name: str,
    codename: str,
    template_file: str = ".github/ISSUE_TEMPLATE/compatibility_report.yml",
):
    """Ensure '<device_name> (<codename>)' is present in the issue template dropdown and 'Other' stays last."""
    if not os.path.exists(template_file):
        return

    with open(template_file, "r", encoding="utf-8") as f:
        content = f.read()

    pattern = re.compile(
        r"(id:\s*device\s*\n\s*attributes:\s*\n\s*label:\s*[^\n]+\n\s*description:\s*[^\n]+\n\s*options:\s*\n)((?:[ \t]*- [^\n]+\n)+)"
    )
    m = pattern.search(content)
    if not m:
        return

    raw_opts = []
    for line in m.group(2).splitlines():
        s = line.strip()
        if s.startswith("- "):
            val = s[2:].strip().strip('"').strip("'")
            if val and not val.lower().startswith("other (please specify"):
                raw_opts.append(val)

    target_entry = f"{device_name} ({codename})"
    existing_lower = {o.lower() for o in raw_opts}
    if target_entry.lower() not in existing_lower:
        raw_opts.append(target_entry)
        print(f"[INFO] Added '{target_entry}' to dropdown options in {template_file}.")

    raw_opts.sort(key=lambda x: x.lower())
    raw_opts.append(OTHER_OPTION_LABEL)

    new_options_block = "\n".join(f'        - "{opt}"' for opt in raw_opts) + "\n"
    updated_content = content[:m.start()] + m.group(1) + new_options_block + content[m.end():]

    if updated_content != content:
        with open(template_file, "w", encoding="utf-8") as f:
            f.write(updated_content)

def emit_validation_error(msg: str):
    """Export validation_error to GITHUB_OUTPUT and exit cleanly so workflow can comment helpful instructions."""
    print(f"[WARN] Validation error: {msg}")
    gh_output = os.environ.get("GITHUB_OUTPUT")
    if gh_output:
        safe_msg = msg.replace("\r", " ").replace("\n", " ")
        with open(gh_output, "a", encoding="utf-8") as f_out:
            f_out.write(f"validation_error={safe_msg}\n")
    sys.exit(0)

def main():
    issue_body = os.environ.get("ISSUE_BODY", "")
    issue_number = os.environ.get("ISSUE_NUMBER", "")
    issue_author = os.environ.get("ISSUE_AUTHOR", "")
    issue_url = os.environ.get("ISSUE_URL", "")

    if not issue_body:
        print("[ERROR] ISSUE_BODY is empty. Exiting.")
        sys.exit(1)

    fields = parse_issue_form(issue_body)
    print("Parsed Fields:", list(fields.keys()))

    device_combined = clean_cell(fields.get("Device (Marketing Name & Codename)", ""))
    is_other_selected = device_combined.lower().startswith("other")

    if is_other_selected:
        other_raw = fields.get("Other Device (Marketing Name & Codename)", "").strip()
        if not other_raw or other_raw in ("_No response_", "None", "—"):
            emit_validation_error(
                "You selected **Other** in the Device dropdown, but left **Other Device (Marketing Name & Codename)** blank. "
                "Please edit your issue and provide your device in the exact format `<Marketing Name> (<codename>)` — for example: `moto g power 5G - 2024 (cancunn)` or `razr+ 2023 (zeekr)`."
            )
        m_other = re.match(r"^(.+?)\s*\(([A-Za-z0-9][A-Za-z0-9_-]{1,31})\)\s*$", other_raw)
        if not m_other:
            emit_validation_error(
                f"Could not parse **Other Device**: `{clean_cell(other_raw)}`. "
                "Please edit your issue to strictly follow our naming convention: `<Marketing Name> (<codename>)` (omit leading 'Motorola', with the lowercase Android board codename in parentheses at the end — e.g., `moto g power 5G - 2024 (cancunn)` or `razr+ 2023 (zeekr)`)."
            )
        raw_name = re.sub(r"^motorola\s+", "", m_other.group(1).strip(), flags=re.IGNORECASE).strip()
        device_name = clean_cell(raw_name)
        codename = clean_cell(m_other.group(2)).lower()
        if (
            len(device_name) < 2
            or "<" in device_name
            or ">" in device_name
            or device_name.lower() in ("marketing name", "other", "device", "unknown")
            or codename in ("codename", "other", "unknown", "device")
        ):
            emit_validation_error(
                f"Invalid placeholder or device identifier `{device_name} ({codename})`. "
                "Please edit your issue with the real Motorola marketing name and Android board codename — e.g., `moto g power 5G - 2024 (cancunn)`."
            )
    elif device_combined and device_combined != "—":
        m = re.match(r"^(.*?)\s*\(([^()]+)\)$", device_combined)
        if m:
            device_name = clean_cell(m.group(1))
            codename = clean_cell(m.group(2))
        else:
            device_name = device_combined
            codename = device_combined
    else:
        device_name = clean_cell(fields.get("Device Marketing Name", ""))
        codename = clean_cell(fields.get("Device Codename", ""))

    model = clean_cell(fields.get("Device Model Number", ""))
    camera_gen_raw = fields.get("Stock Camera Era Restored", "")
    camera_gen = clean_cell(camera_gen_raw.split(" (")[0]) if camera_gen_raw else "—"

    result_raw = fields.get("Test Result", "")
    badge_emoji, result_cat = determine_badge(result_raw)

    custom_rom = clean_cell(fields.get("Custom ROM & Android Version", ""))
    stock_fw = clean_cell(fields.get("Stock Firmware Source / Build", ""))
    features_summary = clean_cell(parse_sensor_summary(fields))

    if not device_name or device_name == "—":
        print("[ERROR] Device Marketing Name missing.")
        sys.exit(1)

    # Format reporter & issue link
    reporter_str = f"[@{issue_author}](https://github.com/{issue_author})" if issue_author else "Community"
    report_link = f"[#{issue_number}]({issue_url})" if issue_number and issue_url else f"#{issue_number}"

    # Build report table row
    new_report_row = f"| {report_link} by {reporter_str} | {custom_rom} | {stock_fw} | {badge_emoji} {result_cat} | {features_summary} |"
    print("New Report Row:", new_report_row)

    os.makedirs("reports", exist_ok=True)

    device_key = re.sub(r"[^a-zA-Z0-9_-]", "", codename.lower())
    if not device_key or device_key == "—":
        device_key = re.sub(r"[^a-zA-Z0-9_-]", "", device_name.lower())

    device_file = os.path.join("reports", f"{device_key}.md")
    issue_marker = f"[#{issue_number}](" if issue_number else None

    # --- 1. Create or Update reports/{device_key}.md ---
    if os.path.exists(device_file):
        print(f"[INFO] Updating existing report page: {device_file}")
        with open(device_file, "r", encoding="utf-8") as f:
            dev_content = f.read()

        table_lines = []
        table_found = False

        for line in dev_content.splitlines():
            if re.match(r"^\|\s*:?---", line):
                table_found = True
                continue
            if table_found and line.strip().startswith("|"):
                if "*no reports yet*" in line.lower():
                    continue
                if issue_marker and issue_marker in line:
                    continue  # Deduplicate on edit/re-run
                table_lines.append(line.strip())

        table_lines.append(new_report_row)
        total_reports = len(table_lines)

        dev_content = re.sub(
            r"- \*\*Current Overall Status:\*\* .*",
            f"- **Current Overall Status:** {badge_emoji} **{result_cat}**",
            dev_content
        )
        dev_content = re.sub(
            r"- \*\*Total Community Reports:\*\* .*",
            f"- **Total Community Reports:** {total_reports}",
            dev_content
        )

        # Update Marketing Name / Community Variant(s) if a new variant name was submitted
        mn_match = re.search(r"- \*\*Marketing Name:\*\* (.*)", dev_content)
        if mn_match:
            existing_names = [n.strip() for n in mn_match.group(1).split(" / ") if n.strip()]
            if device_name.lower() not in {n.lower() for n in existing_names}:
                existing_names.append(device_name)
                combined_mn = " / ".join(existing_names)
                dev_content = dev_content.replace(mn_match.group(0), f"- **Marketing Name:** {combined_mn}")
                dev_content = re.sub(
                    r"^# Device Report: .*",
                    f"# Device Report: {combined_mn} (`{codename}`)",
                    dev_content,
                    count=1,
                    flags=re.MULTILINE,
                )
                if "**Device Source:** Community Reported" not in dev_content:
                    cv_match = re.search(r"- \*\*Community Variant\(s\):\*\* (.*)", dev_content)
                    if cv_match:
                        cv_list = [c.strip() for c in cv_match.group(1).split(" / ") if c.strip()]
                        if device_name.lower() not in {c.lower() for c in cv_list}:
                            cv_list.append(device_name)
                            dev_content = dev_content.replace(
                                cv_match.group(0),
                                f"- **Community Variant(s):** {' / '.join(cv_list)}",
                            )
                    else:
                        dev_content = dev_content.replace(
                            f"- **Marketing Name:** {combined_mn}",
                            f"- **Marketing Name:** {combined_mn}\n- **Community Variant(s):** {device_name}",
                        )

        if camera_gen != "—":
            dev_content = re.sub(
                r"- \*\*Stock Camera Era:\*\* —",
                f"- **Stock Camera Era:** {camera_gen}",
                dev_content,
            )

        if model != "—":
            m_match = re.search(r"- \*\*Model Number\(s\):\*\* (.*)", dev_content)
            if m_match:
                existing_models = m_match.group(1).strip()
                if model not in existing_models and existing_models != "—":
                    updated_models = f"{existing_models}, `{model}`"
                    dev_content = dev_content.replace(m_match.group(0), f"- **Model Number(s):** {updated_models}")
                elif existing_models == "—":
                    dev_content = dev_content.replace(m_match.group(0), f"- **Model Number(s):** `{model}`")

        # Replace table rows
        header_delim = "| :--- | :--- | :--- | :---: | :--- |\n"
        parts = dev_content.split(header_delim, 1)
        if len(parts) != 2:
            parts = dev_content.split("| :--- | :---: | :--- | :--- | :---: | :--- |\n", 1)

        if len(parts) == 2:
            footer_parts = parts[1].split("\n---", 1)
            new_table_content = "\n".join(table_lines) + "\n\n---"
            dev_content = parts[0] + header_delim + new_table_content + (footer_parts[1] if len(footer_parts) == 2 else "")

        with open(device_file, "w", encoding="utf-8") as f:
            f.write(dev_content)

    else:
        print(f"[INFO] Creating new report page: {device_file}")
        total_reports = 1
        model_val = f"`{model}`" if model != "—" else "—"

        new_dev_content = f"""# Device Report: {device_name} (`{codename}`)

<p align="center">
  <a href="../COMPATIBILITY.md"><img src="https://img.shields.io/badge/⬅%20Back%20to-Per--Device%20Compatibility%20Table-blue?style=flat-square" alt="Per-Device Compatibility Table"></a>
  <a href="https://github.com/vrwindsor1/Moto-Camera-Restored/issues/new?template=compatibility_report.yml"><img src="https://img.shields.io/badge/Submit-New%20Report-success?style=flat-square&logo=github" alt="Submit Report"></a>
  <a href="../LICENSE"><img src="https://img.shields.io/badge/License-Apache%202.0-blue.svg?style=flat-square" alt="License"></a>
</p>

## Device Information

- **Marketing Name:** {device_name}
- **Codename:** `{codename}`
- **Model Number(s):** {model_val}
- **Device Source:** Community Reported
- **Stock Camera Era:** {camera_gen}
- **Current Overall Status:** {badge_emoji} **{result_cat}**
- **Total Community Reports:** 1

---

## Community Test Reports

| Report | Custom ROM | Stock Firmware | Outcome | Tested Features / Notes |
| :--- | :--- | :--- | :---: | :--- |
{new_report_row}

---

<p align="center">
  <a href="../COMPATIBILITY.md">⬅ Back to Per-Device Compatibility Table</a> &bull; <a href="../README.md">Installer Documentation</a>
</p>
"""
        with open(device_file, "w", encoding="utf-8") as f:
            f.write(new_dev_content)

    # --- 2. Update COMPATIBILITY.md & Issue Template Dropdown ---
    update_compatibility_md(device_name, device_key, custom_rom, camera_gen, badge_emoji, result_cat)
    ensure_device_in_issue_template(device_name, device_key)

    # --- 3. Set GitHub Action Outputs ---
    gh_output = os.environ.get("GITHUB_OUTPUT")
    if gh_output:
        try:
            with open(gh_output, "a", encoding="utf-8") as f_out:
                f_out.write(f"device_name={device_name}\n")
                f_out.write(f"device_codename={codename}\n")
                f_out.write(f"issue_title=[Compatibility]: {device_name} ({codename})\n")
                f_out.write(f"result_cat={result_cat}\n")
                f_out.write(f"badge_emoji={badge_emoji}\n")
                f_out.write(f"is_working_perfectly={'true' if result_cat == 'Works Perfectly' else 'false'}\n")
            print(f"[INFO] Exported issue_title='[Compatibility]: {device_name} ({codename})' to GITHUB_OUTPUT.")
            print(f"[INFO] Exported result_cat='{result_cat}', is_working_perfectly={'true' if result_cat == 'Works Perfectly' else 'false'} to GITHUB_OUTPUT.")
        except Exception as e:
            print(f"[WARN] Failed to write to GITHUB_OUTPUT: {e}")

    print(f"[SUCCESS] Processed compatibility report for {device_name} ({codename}).")

if __name__ == "__main__":
    main()
