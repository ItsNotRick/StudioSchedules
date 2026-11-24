"""
Shared parser for Mindbody Branded Web (Next.js RSC flight payload) schedule widgets
used by Steps on Broadway and Peridance Center.
"""

import json
import re
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional
from zoneinfo import ZoneInfo

NY_TZ = ZoneInfo("America/New_York")

_FLIGHT_PUSH_RE = re.compile(r'self\.__next_f\.push\(\[\s*1\s*,\s*"')
_RSC_LINE_RE = re.compile(r'^([0-9a-fA-F]+):(\{|\[)', re.M)
_SUB_MARKER_RE = re.compile(r'\(\s*sub(?:stitute)?\s*\)', re.I)
_SUB_WORD_RE = re.compile(r'\b(sub|substitute)\b', re.I)
_VIRTUAL_RE = re.compile(r'\b(virtual|livestream|live\s*stream)\b', re.I)


def decode_next_flight_html(html: str) -> str:
    """Extracts and JSON-unescapes Next.js RSC flight chunks from [html].

    Falls back to single-layer quote/backslash unescaping when a snippet contains
    double-escaped ``\\\"id\\\":\\\"cinst_`` without a ``self.__next_f.push``
    wrapper.
    """
    decoder = json.JSONDecoder()
    chunks: List[str] = []
    pos = 0
    while True:
        m = _FLIGHT_PUSH_RE.search(html, pos)
        if not m:
            break
        str_start = m.end() - 1  # pointing at opening quote
        try:
            decoded, end_idx = decoder.raw_decode(html, str_start)
            if isinstance(decoded, str):
                chunks.append(decoded)
            pos = end_idx
        except json.JSONDecodeError:
            pos = m.end()

    if chunks:
        return "\n".join(chunks)

    if '"id":"cinst_' not in html and r'\"id\":\"cinst_' in html:
        return re.sub(r'\\(["\\])', lambda m: m.group(1), html)
    return html


def _find_enclosing_brace(text: str, pos: int) -> Optional[int]:
    """Walks backwards from [pos] to the enclosing '{', ignoring braces in strings."""
    depth = 0
    i = pos - 1
    in_string = False
    while i >= 0:
        ch = text[i]
        if ch == '"':
            # Count consecutive preceding backslashes to detect escaped quotes.
            bs = 0
            j = i - 1
            while j >= 0 and text[j] == "\\":
                bs += 1
                j -= 1
            if bs % 2 == 0:
                in_string = not in_string
        elif not in_string:
            if ch == "}":
                depth += 1
            elif ch == "{":
                if depth == 0:
                    return i
                depth -= 1
        i -= 1
    return None


def _parse_enclosing_object(
    text: str, anchor_pos: int, decoder: json.JSONDecoder
) -> Optional[Dict[str, Any]]:
    brace_pos = _find_enclosing_brace(text, anchor_pos)
    if brace_pos is None:
        return None
    try:
        obj, _ = decoder.raw_decode(text, brace_pos)
        return obj if isinstance(obj, dict) else None
    except json.JSONDecodeError:
        return None


def _collect_staff_maps(
    text: str, decoder: json.JSONDecoder
) -> tuple[Dict[str, str], Dict[str, Any]]:
    """Builds staff_by_id and Next.js RSC $ref tables from decoded flight text."""
    staff_by_id: Dict[str, str] = {}
    rsc_refs: Dict[str, Any] = {}

    for m in _RSC_LINE_RE.finditer(text):
        ref_key = f"${m.group(1)}"
        try:
            val, _ = decoder.raw_decode(text, m.start(2))
            rsc_refs[ref_key] = val
            if isinstance(val, dict) and "displayLabel" in val and "id" in val:
                label = val.get("displayLabel")
                if isinstance(label, str) and label.strip():
                    staff_by_id[str(val["id"])] = label.strip()
        except json.JSONDecodeError:
            pass

    for m in re.finditer(r'"displayLabel"\s*:', text):
        obj = _parse_enclosing_object(text, m.start(), decoder)
        if not obj:
            continue
        label = obj.get("displayLabel")
        obj_id = obj.get("id")
        if isinstance(label, str) and label.strip() and obj_id is not None:
            staff_by_id[str(obj_id)] = label.strip()

    return staff_by_id, rsc_refs


def _extract_staff_name(
    val: Any,
    staff_by_id: Dict[str, str],
    rsc_refs: Dict[str, Any],
) -> Optional[str]:
    if isinstance(val, str) and val.startswith("$"):
        val = rsc_refs.get(val, val)
    if isinstance(val, dict):
        if isinstance(val.get("displayLabel"), str) and val["displayLabel"].strip():
            return val["displayLabel"].strip()
        if isinstance(val.get("name"), str) and val["name"].strip():
            return val["name"].strip()
        if val.get("id") is not None:
            return staff_by_id.get(str(val["id"]))
    elif isinstance(val, str) and val.strip() and not val.startswith("$"):
        return staff_by_id.get(val.strip(), val.strip())
    return None


def _resolve_instructor(
    obj: Optional[Dict[str, Any]],
    chunk: str,
    staff_by_id: Dict[str, str],
    rsc_refs: Dict[str, Any],
) -> tuple[str, bool, Optional[str]]:
    """Extracts (instructor, is_substitute, regular_instructor) from a cinst object or chunk."""
    raw_inst: Optional[str] = None
    is_sub = False
    regular_inst: Optional[str] = None

    if obj:
        is_sub = bool(obj.get("isSubstitute") or obj.get("substitute"))
        if isinstance(obj.get("displayLabel"), str) and obj["displayLabel"].strip():
            raw_inst = obj["displayLabel"].strip()
        else:
            staff_val = obj.get("staff") or obj.get("instructor")
            if isinstance(staff_val, list):
                names: List[str] = []
                for entry in staff_val:
                    name = _extract_staff_name(entry, staff_by_id, rsc_refs)
                    if name and name not in names:
                        names.append(name)
                if names:
                    raw_inst = ", ".join(names)
            else:
                raw_inst = _extract_staff_name(staff_val, staff_by_id, rsc_refs)

        if not raw_inst:
            for id_key in ("staffId", "instructorId"):
                sid = obj.get(id_key)
                if sid is not None and str(sid) in staff_by_id:
                    raw_inst = staff_by_id[str(sid)]
                    break

        reg_val = obj.get("regularInstructor") or obj.get("regularStaff")
        if isinstance(reg_val, dict) and isinstance(reg_val.get("displayLabel"), str):
            regular_inst = reg_val["displayLabel"].strip()
        elif isinstance(reg_val, str) and reg_val.strip():
            regular_inst = reg_val.strip()

    if not raw_inst:
        inst_m = re.search(r'"displayLabel"\s*:\s*("(?:[^"\\]|\\.)*")', chunk)
        if inst_m:
            try:
                raw_inst = json.loads(inst_m.group(1)).strip()
            except json.JSONDecodeError:
                pass
        if not raw_inst:
            ref_list_m = re.search(r'"staff"\s*:\s*\[\s*"(\$[0-9a-fA-F]+)"', chunk)
            if ref_list_m:
                raw_inst = _extract_staff_name(
                    ref_list_m.group(1), staff_by_id, rsc_refs
                )
        if not raw_inst:
            for id_key in ("staffId", "instructorId"):
                sid_m = re.search(rf'"{id_key}"\s*:\s*"?([^",}}\s]+)"?', chunk)
                if sid_m and sid_m.group(1) in staff_by_id:
                    raw_inst = staff_by_id[sid_m.group(1)]
                    break

    if not obj:
        is_sub = re.search(r'"(?:isSubstitute|substitute)"\s*:\s*true\b', chunk) is not None

    raw_inst = raw_inst or "Staff"
    if _SUB_WORD_RE.search(raw_inst):
        is_sub = True
    cleaned = _SUB_MARKER_RE.sub("", raw_inst)
    cleaned = re.sub(r'\s+_+$', "", cleaned).strip() or "Staff"
    return cleaned, is_sub, regular_inst


def parse_mindbody_widget_sessions(
    html: str,
    *,
    studio_id: str,
    id_prefix: str,
    booking_url: str,
    exclude_virtual: bool = False,
    strip_in_studio_prefix: bool = False,
) -> List[Dict[str, Any]]:
    """Parses cinst_* sessions from a Mindbody Branded Web schedule HTML page."""
    text = decode_next_flight_html(html)
    decoder = json.JSONDecoder(strict=False)
    staff_by_id, rsc_refs = _collect_staff_maps(text, decoder)

    id_matches = list(re.finditer(r'"id"\s*:\s*"(cinst_[^"]+)"', text))
    sessions: List[Dict[str, Any]] = []
    seen = set()

    for idx, m in enumerate(id_matches):
        cid = m.group(1)
        if cid in seen:
            continue
        seen.add(cid)

        next_start = id_matches[idx + 1].start() if idx + 1 < len(id_matches) else len(text)
        chunk = text[m.start():next_start]
        obj = _parse_enclosing_object(text, m.start(), decoder)

        if obj:
            name_val = obj.get("name")
            name = name_val.strip() if isinstance(name_val, str) else ""
            sdt_val = obj.get("startDateTime")
            sdt = sdt_val.strip() if isinstance(sdt_val, str) else ""
            dur_val = obj.get("duration")
            dur = int(dur_val) if isinstance(dur_val, (int, float)) else 90
            is_cancelled = bool(obj.get("cancelled") or obj.get("canceled"))
            is_virtual = bool(obj.get("isVirtual") or obj.get("virtual"))
        else:
            name_m = re.search(r'"name"\s*:\s*("(?:[^"\\]|\\.)*")', chunk)
            sdt_m = re.search(r'"startDateTime"\s*:\s*("(?:[^"\\]|\\.)*")', chunk)
            if not name_m or not sdt_m:
                continue
            try:
                name = json.loads(name_m.group(1)).strip()
                sdt = json.loads(sdt_m.group(1)).strip()
            except json.JSONDecodeError:
                continue
            dur_m = re.search(r'"duration"\s*:\s*(\d+)', chunk)
            dur = int(dur_m.group(1)) if dur_m else 90
            is_cancelled = re.search(r'"cancell?ed"\s*:\s*true\b', chunk) is not None
            is_virtual = re.search(r'"(?:isVirtual|virtual)"\s*:\s*true\b', chunk) is not None

        if not name or not sdt:
            continue

        clean_name = name.replace("In-Studio ", "").strip() if strip_in_studio_prefix else name
        if not clean_name:
            continue

        if exclude_virtual and (is_virtual or _VIRTUAL_RE.search(clean_name)):
            continue

        try:
            dt_parsed = datetime.fromisoformat(sdt.replace("Z", "+00:00"))
            if dt_parsed.tzinfo is None:
                dt_parsed = dt_parsed.replace(tzinfo=timezone.utc)
            dt_local = dt_parsed.astimezone(NY_TZ)
            service_date = dt_local.strftime("%Y-%m-%d")
            start_min = dt_local.hour * 60 + dt_local.minute
        except Exception as e:
            print(f"Warning: skipping {studio_id} session '{clean_name}' with malformed startDateTime '{sdt}': {e}")
            continue

        instructor, is_sub, regular_inst = _resolve_instructor(obj, chunk, staff_by_id, rsc_refs)
        session_id = f"{id_prefix}_{service_date}_{start_min}_{cid[-8:]}"

        record: Dict[str, Any] = {
            "id": session_id,
            "studioId": studio_id,
            "rawClassTitle": clean_name,
            "serviceDate": service_date,
            "startMin": start_min,
            "endMin": start_min + dur,
            "tz": "America/New_York",
            "instructor": instructor,
            "isSubstitute": is_sub,
            "status": "cancelled" if is_cancelled else "scheduled",
            "bookingUrl": booking_url,
        }
        if regular_inst:
            record["regularInstructor"] = regular_inst
        sessions.append(record)

    return sessions
