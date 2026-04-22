#!/usr/bin/env python3
import argparse
import email.utils
import gzip
import html
import io
import json
import os
import pwd
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.parse
import xml.etree.ElementTree as ET
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path


DEFAULT_CATEGORY = "cs.DB"
DEFAULT_FEED_URL = "https://export.arxiv.org/api/query"
OUTPUT_FILE_NAME = "cs.DB-summary.json"
APP_GROUP = "group.me.wanshenl.KapiBoard"
DEFAULT_CODEX_BIN = "/Applications/Codex.app/Contents/Resources/codex"
WIDGET_BUNDLE_IDS = [
    "me.wanshenl.KapiBoard.WidgetExtension",
    "me.wanshenl.KapiBoard.DetailWidgetExtension",
    "me.wanshenl.KapiBoard.ArxivWidgetExtension",
]

STOPWORDS = {
    "a", "an", "and", "are", "as", "at", "based", "by", "data", "database",
    "databases", "for", "from", "in", "into", "is", "learning", "of", "on",
    "or", "over", "query", "systems", "the", "to", "towards", "using", "via",
    "with",
}

CATEGORY_RULES = [
    ("ML for DB", ("learn", "neural", "rag", "llm", "model", "agent", "embedding", "graph")),
    ("Query Processing", ("query", "optimizer", "optimization", "join", "index")),
    ("Transactions", ("transaction", "concurrency", "isolation", "serializ")),
    ("Storage/Systems", ("storage", "system", "distributed", "engine", "cache")),
    ("Security/Policy", ("privacy", "compliance", "policy", "access control", "security")),
    ("Benchmarks", ("benchmark", "dataset", "mutant", "evaluation")),
    ("Analytics/Visualization", ("analytics", "visual", "dashboard", "workflow")),
]


def utc_now_iso():
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_date(value):
    if not value:
        return None
    try:
        parsed = email.utils.parsedate_to_datetime(value)
    except (TypeError, ValueError):
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_atom_date(value):
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def clean_text(value):
    value = html.unescape(value or "")
    value = re.sub(r"<[^>]+>", " ", value)
    value = re.sub(r"\s+", " ", value)
    return value.strip()


def clean_latex_text(value):
    value = html.unescape(value or "")
    value = re.sub(r"(?<!\\)%.*", " ", value)
    value = value.replace("~", " ")
    value = value.replace("\\\\", ", ")
    value = re.sub(r"\\[,;:! ]", " ", value)
    value = re.sub(r"\$?\^\{[^}]+\}\$?", " ", value)
    value = re.sub(r"\\textsuperscript\{[^}]+\}", " ", value)
    value = re.sub(r"\\[a-zA-Z]+\*?(?:\[[^\]]*\])?\{([^{}]*)\}", r"\1", value)
    value = re.sub(r"\\[a-zA-Z]+\*?", " ", value)
    value = re.sub(r"[{}$]", " ", value)
    value = re.sub(r"\s*;\s*$", "", value)
    value = re.sub(r"\s+", " ", value)
    return value.strip(" ,;")


def first_sentence(value, max_length=180):
    value = clean_text(value)
    if not value:
        return ""
    match = re.search(r"(?<=[.!?])\s+", value)
    sentence = value[: match.start()].strip() if match else value
    if len(sentence) <= max_length:
        return sentence
    return sentence[: max_length - 1].rstrip() + "..."


def split_authors(value):
    value = clean_text(value)
    if not value:
        return []
    parts = re.split(r"\s*,\s*|\s+and\s+", value)
    return [part.strip() for part in parts if part.strip()]


def arxiv_id_from_link(link):
    match = re.search(r"arxiv\.org/(?:abs|pdf)/([^?#]+)", link or "")
    if match:
        return match.group(1).removesuffix(".pdf")
    return link or ""


def arxiv_id_from_api_id(api_id):
    match = re.search(r"arxiv\.org/abs/([^?#]+)", api_id or "")
    if match:
        return match.group(1)
    return api_id or ""


def base_arxiv_id(arxiv_id):
    return re.sub(r"v\d+$", "", arxiv_id or "")


def extract_braced_values(text, command):
    values = []
    command_pattern = re.compile(rf"(?<![A-Za-z])\\{re.escape(command)}\*?(?:\[[^\]]*\])?\s*\{{")
    for match in command_pattern.finditer(text):
        brace = match.end() - 1
        depth = 0
        for position in range(brace, len(text)):
            char = text[position]
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    values.append(text[brace + 1:position])
                    break
    return values


def extract_markers(value):
    markers = []
    for match in re.finditer(r"\$?\^\{([^}]+)\}\$?|\\textsuperscript\{([^}]+)\}", value or ""):
        raw = next(group for group in match.groups() if group)
        markers.extend(part.strip() for part in re.split(r"[,;]", raw) if part.strip())
    return markers


def compact_institution(value):
    value = clean_latex_text(value)
    if not value:
        return ""
    parts = [part.strip() for part in value.split(",") if part.strip()]
    keywords = (
        "University", "Institute", "College", "School", "Laboratory", "Lab",
        "Center", "Centre", "Corporation", "Inc.", "Ltd", "Company",
        "Microsoft", "IIIT", "Simula"
    )
    selected = [part for part in parts if any(keyword in part for keyword in keywords)]
    if selected:
        value = selected[-1]
        generic_tail = {"Ltd", "Inc.", "Company", "Corporation"}
        subunit_prefixes = ("School of", "Department of", "Faculty of")
        if len(selected) > 1 and value in generic_tail:
            value = selected[-2]
        elif len(selected) > 1 and value.startswith(subunit_prefixes):
            previous = selected[-2]
            if any(keyword in previous for keyword in ("University", "College", "Institute")):
                value = previous
    elif parts:
        value = parts[0]
    value = re.sub(r"^the\s+", "", value, flags=re.IGNORECASE)
    value = value.replace(" and,", ",")
    return value[:120].rstrip()


def marked_institution_segments(value):
    matches = list(re.finditer(r"\$?\^\{([^}]+)\}\$?|\\textsuperscript\{([^}]+)\}", value or ""))
    if not matches:
        institution = compact_institution(value)
        return [([], institution)] if institution else []

    segments = []
    for index, match in enumerate(matches):
        marker = next(group for group in match.groups() if group)
        start = match.end()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(value)
        institution = compact_institution(value[start:end])
        if institution:
            markers = [part.strip() for part in re.split(r"[,;]", marker) if part.strip()]
            segments.append((markers, institution))
    return segments


def split_latex_authors(author_block):
    block = re.sub(r"(?<!\\)%.*", " ", author_block or "")
    block = block.replace("\\and", ",")
    block = block.replace("\\\\", ",")
    parts = re.split(r"\s*,\s*|\s+ and\s+", block)
    authors = []
    for part in parts:
        name = clean_latex_text(part)
        if name:
            authors.append({"name": name, "markers": extract_markers(part)})
    return authors


def parse_affiliations_from_latex(text, authors):
    ieee_names = extract_braced_values(text, "IEEEauthorblockN")
    ieee_affiliations = extract_braced_values(text, "IEEEauthorblockA")
    if ieee_names and ieee_affiliations:
        by_author = {}
        for index, raw_name in enumerate(ieee_names):
            if index >= len(ieee_affiliations):
                break
            institution = compact_institution(ieee_affiliations[index])
            if not institution:
                continue
            name = clean_latex_text(raw_name)
            by_author[name] = institution
            if index < len(authors):
                by_author[authors[index]] = institution
        if by_author:
            return by_author

    author_blocks = extract_braced_values(text, "author")
    if not author_blocks:
        return {}

    parsed_authors = split_latex_authors(author_blocks[0])
    institutions = []
    for command in ("institution", "orgname", "affil", "affiliation", "institute", "address"):
        for value in extract_braced_values(text, command):
            for markers, institution in marked_institution_segments(value):
                institutions.append({"markers": markers, "institution": institution})

    marker_map = {}
    unmarked = []
    for institution in institutions:
        if institution["markers"]:
            for marker in institution["markers"]:
                marker_map[marker] = institution["institution"]
        else:
            unmarked.append(institution["institution"])

    by_author = {}
    for index, author in enumerate(parsed_authors):
        institution = ""
        for marker in author["markers"]:
            if marker in marker_map:
                institution = marker_map[marker]
                break
        if institution:
            by_author[author["name"]] = institution
            if index < len(authors):
                by_author[authors[index]] = institution

    by_author.update(parse_ieee_thanks_affiliations(text, authors))
    return by_author


def parse_ieee_thanks_affiliations(text, authors):
    by_author = {}
    plain = clean_latex_text(text)
    for sentence in re.split(r"(?<=[.])\s+", plain):
        if "Josiah Carberry" in sentence:
            continue
        if " with " not in sentence and " independent researcher" not in sentence:
            continue
        if "(e-mail" in sentence:
            sentence = sentence.split("(e-mail", 1)[0]
        if " are with " in sentence:
            names_part, institution_part = sentence.split(" are with ", 1)
        elif " is with " in sentence:
            names_part, institution_part = sentence.split(" is with ", 1)
        elif " is an independent researcher" in sentence:
            names_part = sentence.split(" is an independent researcher", 1)[0]
            institution_part = "Independent researcher"
        else:
            continue
        institution = compact_institution(institution_part)
        if not institution:
            continue
        for author in authors:
            if author in names_part:
                by_author[author] = institution
    return by_author


def fetch_source_text(arxiv_id):
    source_id = base_arxiv_id(arxiv_id)
    if not source_id:
        return ""
    command = [
        "/usr/bin/curl",
        "--fail",
        "--silent",
        "--show-error",
        "--location",
        "--max-time",
        "30",
        "--user-agent",
        "KapiBoard/1.0 (+https://arxiv.org)",
        f"https://arxiv.org/e-print/{source_id}",
    ]
    try:
        result = subprocess.run(command, capture_output=True, check=True, timeout=35)
    except Exception:
        return ""

    data = result.stdout
    chunks = []
    try:
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:*") as archive:
            for member in archive.getmembers():
                if not member.isfile() or not member.name.lower().endswith((".tex", ".ltx")):
                    continue
                extracted = archive.extractfile(member)
                if extracted is None:
                    continue
                chunks.append(extracted.read(250_000).decode("utf-8", errors="ignore"))
                if len(chunks) >= 6:
                    break
    except tarfile.TarError:
        try:
            chunks.append(gzip.decompress(data).decode("utf-8", errors="ignore"))
        except Exception:
            try:
                chunks.append(data.decode("utf-8", errors="ignore"))
            except Exception:
                return ""

    return "\n".join(chunks)


def enrich_entries_with_affiliations(entries):
    for entry in entries:
        text = fetch_source_text(entry.get("id", ""))
        if not text:
            entry["firstAuthorInstitution"] = ""
            entry["authorInstitutions"] = []
            continue
        by_author = parse_affiliations_from_latex(text, entry.get("authors", []))
        author_institutions = [
            by_author.get(author, "")
            for author in entry.get("authors", [])
        ]
        entry["firstAuthorInstitution"] = author_institutions[0] if author_institutions else ""
        entry["authorInstitutions"] = author_institutions
    return entries


def api_url(api_base_url, category, target_date, limit):
    day = target_date.strftime("%Y%m%d")
    query = f"cat:{category} AND submittedDate:[{day}0000 TO {day}2359]"
    params = {
        "search_query": query,
        "start": "0",
        "max_results": str(limit),
        "sortBy": "submittedDate",
        "sortOrder": "ascending",
    }
    return f"{api_base_url}?{urllib.parse.urlencode(params)}"


def fetch_entries(api_base_url, category, target_date, limit):
    url = api_url(api_base_url, category, target_date, limit)
    command = [
        "/usr/bin/curl",
        "--fail",
        "--silent",
        "--show-error",
        "--location",
        "--max-time",
        "25",
        "--user-agent",
        "KapiBoard/1.0 (+https://export.arxiv.org/api/query)",
        url,
    ]
    result = subprocess.run(command, capture_output=True, check=True, timeout=25)
    body = result.stdout

    root = ET.fromstring(body)
    atom = {"atom": "http://www.w3.org/2005/Atom"}

    entries = []
    for item in root.findall("atom:entry", atom)[:limit]:
        api_id = clean_text(item.findtext("atom:id", namespaces=atom))
        title = clean_text(item.findtext("atom:title", namespaces=atom))
        abstract = clean_text(item.findtext("atom:summary", namespaces=atom))
        pub_date = parse_atom_date(item.findtext("atom:published", namespaces=atom))
        authors = [
            clean_text(author.findtext("atom:name", namespaces=atom))
            for author in item.findall("atom:author", atom)
        ]
        authors = [author for author in authors if author]
        first_author = authors[0] if authors else ""
        arxiv_id = arxiv_id_from_api_id(api_id) or title
        entries.append(
            {
                "id": arxiv_id,
                "title": title,
                "url": f"https://arxiv.org/abs/{arxiv_id}",
                "category": "",
                "firstAuthor": first_author,
                "firstAuthorInstitution": "",
                "authors": authors,
                "authorInstitutions": [],
                "summary": abstract,
                "publishedAt": pub_date,
                "abstract": abstract,
            }
        )

    return url, entries


def common_terms(entries):
    counter = Counter()
    for entry in entries:
        words = re.findall(r"[A-Za-z][A-Za-z0-9-]{3,}", entry["title"].lower())
        counter.update(word for word in words if word not in STOPWORDS)
    return [word for word, _ in counter.most_common(4)]


def default_digest(entries):
    if not entries:
        return ["No cs.DB papers were found for the target date in the arXiv API."]

    counts = categorize_entries(entries)
    count_text = ", ".join(f"{name} {count}" for name, count in counts.items())
    terms = common_terms(entries)
    sentence = f"{len(entries)} cs.DB papers"
    if count_text:
        sentence += f" were found across {count_text}"
    if terms:
        sentence += f", with recurring title terms including {', '.join(terms)}"
    sentence += f"; the most recent paper was {entries[0]['title']}."
    return [sentence]


def categorize_entries(entries):
    counts = Counter()
    for entry in entries:
        text = f"{entry.get('title', '')} {entry.get('abstract', '')}".lower()
        matched = False
        for category, terms in CATEGORY_RULES:
            if any(term in text for term in terms):
                counts[category] += 1
                entry["category"] = category
                matched = True
                break
        if not matched:
            counts["Other DB"] += 1
            entry["category"] = "Other DB"
    return dict(counts)


def category_counts_list(counts):
    return [
        {"category": str(category), "count": int(count)}
        for category, count in sorted(counts.items(), key=lambda item: (-int(item[1]), str(item[0])))
    ]


def category_counts_from_papers(paper_categories):
    counts = Counter()
    for item in paper_categories:
        category = str(item.get("category", "")).strip()
        if category:
            counts[category] += 1
    return category_counts_list(counts)


def apply_paper_categories(entries, paper_categories):
    by_id = {
        str(item.get("id", "")).strip(): str(item.get("category", "")).strip()
        for item in paper_categories
        if str(item.get("id", "")).strip() and str(item.get("category", "")).strip()
    }
    for entry in entries:
        category = by_id.get(str(entry.get("id", "")).strip())
        if category:
            entry["category"] = category


def run_external_summarizer(command, payload):
    process = subprocess.run(
        command,
        input=json.dumps(payload),
        text=True,
        capture_output=True,
        check=True,
    )
    result = json.loads(process.stdout)
    digest = result.get("digest")
    paper_categories = result.get("paperCategories")
    items = result.get("items")
    if not isinstance(digest, list):
        raise ValueError("summarizer output must include digest: [String]")
    if paper_categories is not None and not isinstance(paper_categories, list):
        raise ValueError("summarizer output paperCategories must be a list when present")
    if items is not None and not isinstance(items, list):
        raise ValueError("summarizer output items must be a list when present")
    return digest, paper_categories, items


def codex_output_schema():
    paper_category = {
        "type": "object",
        "additionalProperties": False,
        "properties": {
            "id": {"type": "string"},
            "title": {"type": "string"},
            "category": {"type": "string"},
        },
        "required": ["id", "title", "category"],
    }
    item = {
        "type": "object",
        "additionalProperties": False,
        "properties": {
            "id": {"type": "string"},
            "title": {"type": "string"},
            "url": {"type": "string"},
            "category": {"type": "string"},
            "firstAuthor": {"type": "string"},
            "firstAuthorInstitution": {"type": "string"},
            "authors": {"type": "array", "items": {"type": "string"}},
            "authorInstitutions": {"type": "array", "items": {"type": "string"}},
            "summary": {"type": "string"},
            "publishedAt": {"type": ["string", "null"]},
        },
        "required": [
            "id", "title", "url", "category", "firstAuthor", "firstAuthorInstitution",
            "authors", "authorInstitutions", "summary", "publishedAt"
        ],
    }
    return {
        "type": "object",
        "additionalProperties": False,
        "properties": {
            "digest": {
                "type": "array",
                "minItems": 1,
                "maxItems": 1,
                "items": {"type": "string"},
            },
            "paperCategories": {
                "type": "array",
                "items": paper_category,
            },
            "items": {
                "type": "array",
                "maxItems": 5,
                "items": item,
            },
        },
        "required": ["digest", "paperCategories", "items"],
    }


def codex_prompt(payload):
    compact_entries = []
    for entry in payload["entries"]:
        compact_entries.append(
            {
                "id": entry.get("id", ""),
                "title": entry.get("title", ""),
                "url": entry.get("url", ""),
                "category": entry.get("category", ""),
                "firstAuthor": entry.get("firstAuthor", ""),
                "firstAuthorInstitution": entry.get("firstAuthorInstitution", ""),
                "authors": entry.get("authors", []),
                "authorInstitutions": entry.get("authorInstitutions", []),
                "publishedAt": entry.get("publishedAt"),
                "abstract": entry.get("abstract", ""),
            }
        )

    task = {
        "category": payload["category"],
        "source": payload["source"],
        "pulledAt": payload["pulledAt"],
        "targetDate": payload["targetDate"],
        "entries": compact_entries,
    }
    return (
        "Summarize the previous day's arXiv cs.DB Atom API results for a compact macOS widget.\n"
        "Return JSON matching the provided schema only.\n"
        "Rules:\n"
        "- digest: exactly one coherent, concise paragraph about the big picture across the day's papers.\n"
        "- Do not use bullets, numbering, headings, markdown, or line breaks inside digest.\n"
        "- Emphasize the overall trend of the batch, not a paper-by-paper list.\n"
        "- Include the most notable or surprising claim if one exists.\n"
        "- Include whether any paper seems to open a genuinely new line of research; if none does, state that briefly.\n"
        "- Prefer database systems framing: data management, query processing, indexing, transactions, storage, governance, analytics, and ML/RAG for DBs.\n"
        "- paperCategories: assign every input paper exactly one loose SIGMOD/VLDB-style bucket. Use objects with the paper id, title, and category. Good buckets include ML for DB, Query Processing, Transactions, Storage/Systems, Security/Policy, Benchmarks, Analytics/Visualization, or Other DB.\n"
        "- items: return an empty array; the app preserves the full paper list directly from arXiv for the full dashboard.\n"
        "- Avoid generic filler like 'several papers explore'; be specific about the intellectual signal.\n\n"
        f"Input JSON:\n{json.dumps(task, ensure_ascii=True)}\n"
    )


def resolve_codex_bin(configured=None):
    if configured:
        expanded = Path(configured).expanduser()
        if expanded.exists():
            return str(expanded)
        found = shutil.which(configured)
        if found:
            return found

    env_value = os.environ.get("KAPIBOARD_CODEX_BIN")
    if env_value:
        return resolve_codex_bin(env_value)

    found = shutil.which("codex")
    if found:
        return found

    if Path(DEFAULT_CODEX_BIN).exists():
        return DEFAULT_CODEX_BIN

    return None


def run_codex_summarizer(payload, codex_bin):
    with tempfile.TemporaryDirectory(prefix="kapiboard-codex-") as temp_dir:
        schema_path = Path(temp_dir) / "schema.json"
        output_path = Path(temp_dir) / "summary.json"
        schema_path.write_text(json.dumps(codex_output_schema()), encoding="utf-8")

        command = [
            codex_bin,
            "exec",
            "--skip-git-repo-check",
            "--sandbox",
            "read-only",
            "--output-schema",
            str(schema_path),
            "--output-last-message",
            str(output_path),
            "-",
        ]
        subprocess.run(
            command,
            input=codex_prompt(payload),
            text=True,
            capture_output=True,
            check=True,
            timeout=180,
        )

        result = json.loads(output_path.read_text(encoding="utf-8"))

    digest = result.get("digest")
    paper_categories = result.get("paperCategories")
    items = result.get("items")
    if not isinstance(digest, list) or not digest:
        raise ValueError("Codex output must include non-empty digest: [String]")
    if not isinstance(paper_categories, list):
        raise ValueError("Codex output must include paperCategories: [{id, title, category}]")
    if not isinstance(items, list):
        raise ValueError("Codex output must include items: [Object]")
    return digest, paper_categories, items


def parse_iso_datetime(value):
    if not value:
        return None
    if isinstance(value, str) and value.endswith("Z"):
        value = value[:-1] + "+00:00"
    try:
        return datetime.fromisoformat(value)
    except (TypeError, ValueError):
        return None


def local_date_from_iso(value):
    parsed = parse_iso_datetime(value)
    if parsed is None:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone().date()


def parse_target_date(value):
    if value:
        return datetime.strptime(value, "%Y-%m-%d").date()
    return datetime.now().astimezone().date() - timedelta(days=1)


def format_date_label(day):
    if sys.platform == "win32":
        return day.strftime("%b %#d")
    return day.strftime("%b %-d")


def filter_entries_for_target_date(entries, target_date):
    filtered = [
        entry for entry in entries
        if local_date_from_iso(entry.get("publishedAt")) == target_date
    ]
    return filtered


def load_digest_for_target(paths, target_date):
    target = target_date.isoformat()
    for path in paths:
        try:
            digest = json.loads(path.read_text(encoding="utf-8"))
        except (FileNotFoundError, json.JSONDecodeError, OSError):
            continue
        if digest.get("status") == "ready" and digest.get("targetDate") == target:
            return digest, path
    return None, None


def real_home():
    return Path(pwd.getpwuid(os.getuid()).pw_dir)


def output_paths(explicit_path=None):
    if explicit_path:
        primary = Path(explicit_path).expanduser()
        return [primary]
    elif os.environ.get("KAPIBOARD_ARXIV_DIGEST_PATH"):
        primary = Path(os.environ["KAPIBOARD_ARXIV_DIGEST_PATH"]).expanduser()
    else:
        primary = real_home() / ".kapiboard" / "arxiv" / OUTPUT_FILE_NAME

    paths = [primary]
    home = real_home()
    paths.append(home / "Library" / "Group Containers" / APP_GROUP / "arxiv" / OUTPUT_FILE_NAME)

    for bundle_id in WIDGET_BUNDLE_IDS:
        paths.append(
            home
            / "Library"
            / "Containers"
            / bundle_id
            / "Data"
            / "Library"
            / "Group Containers"
            / APP_GROUP
            / "arxiv"
            / OUTPUT_FILE_NAME
        )

    seen = set()
    unique = []
    for path in paths:
        key = str(path)
        if key not in seen:
            seen.add(key)
            unique.append(path)
    return unique


def write_digest(digest, paths):
    encoded = json.dumps(digest, indent=2, sort_keys=True) + "\n"
    wrote_any = False
    for path in paths:
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            tmp = path.with_suffix(path.suffix + ".tmp")
            tmp.write_text(encoded, encoding="utf-8")
            tmp.replace(path)
            wrote_any = True
        except OSError as error:
            print(f"Warning: could not write arXiv digest to {path}: {error}", file=sys.stderr)

    if not wrote_any:
        raise OSError("Could not write arXiv digest to any configured path.")


def main():
    parser = argparse.ArgumentParser(description="Update the KapiBoard arXiv cs.DB digest file.")
    parser.add_argument("--category", default=DEFAULT_CATEGORY)
    parser.add_argument("--feed-url", default=DEFAULT_FEED_URL, help="arXiv API base URL.")
    parser.add_argument("--limit", type=int, default=100, help="Maximum papers to fetch for one target date.")
    parser.add_argument("--output")
    parser.add_argument("--target-date", help="Date to summarize as YYYY-MM-DD. Defaults to yesterday in the local timezone.")
    parser.add_argument("--force", action="store_true", help="Regenerate even if the target date's digest already exists.")
    parser.add_argument("--no-codex", action="store_true", help="Do not use the local Codex CLI summarizer.")
    parser.add_argument("--skip-affiliations", action="store_true", help="Skip best-effort arXiv source affiliation extraction.")
    parser.add_argument("--codex-bin", help="Path to the Codex CLI. Defaults to KAPIBOARD_CODEX_BIN, PATH, then the Codex.app bundled CLI.")
    parser.add_argument(
        "--summarizer-command",
        nargs="+",
        default=os.environ.get("KAPIBOARD_ARXIV_SUMMARIZER"),
        help="Optional command that reads raw JSON on stdin and returns JSON with digest/paperCategories/items. Overrides the Codex CLI summarizer.",
    )
    args = parser.parse_args()

    if isinstance(args.summarizer_command, str):
        args.summarizer_command = args.summarizer_command.split() if args.summarizer_command else None

    target_date = parse_target_date(args.target_date)
    paths = output_paths(args.output)
    if not args.force:
        existing, existing_path = load_digest_for_target(paths, target_date)
        if existing is not None:
            write_digest(existing, paths)
            print(f"Skipped arXiv summarization; digest for {target_date.isoformat()} already exists at {existing_path}.")
            print("Mirrored arXiv digest:")
            for path in paths:
                print(f"- {path}")
            return

    pulled_at = utc_now_iso()
    actual_feed_url, entries = fetch_entries(args.feed_url, args.category, target_date, args.limit)
    if entries and not args.skip_affiliations:
        entries = enrich_entries_with_affiliations(entries)
    digest_points = default_digest(entries)
    category_counts = category_counts_list(categorize_entries(entries))

    if args.summarizer_command:
        payload = {
            "category": args.category,
            "source": actual_feed_url,
            "pulledAt": pulled_at,
            "targetDate": target_date.isoformat(),
            "entries": entries,
        }
        digest_points, paper_categories, summarized_items = run_external_summarizer(args.summarizer_command, payload)
        if paper_categories:
            apply_paper_categories(entries, paper_categories)
            category_counts = category_counts_from_papers(paper_categories)
        summarizer = "external"
    elif not args.no_codex and entries:
        codex_bin = resolve_codex_bin(args.codex_bin)
        if codex_bin:
            payload = {
                "category": args.category,
                "source": actual_feed_url,
                "pulledAt": pulled_at,
                "targetDate": target_date.isoformat(),
                "entries": entries,
            }
            try:
                digest_points, paper_categories, summarized_items = run_codex_summarizer(payload, codex_bin)
                apply_paper_categories(entries, paper_categories)
                category_counts = category_counts_from_papers(paper_categories)
                summarizer = "codex"
            except Exception as error:
                print(f"Codex summarizer failed; using local fallback: {error}", file=sys.stderr)
                summarizer = "fallback"
        else:
            print("Codex CLI not found; using local fallback.", file=sys.stderr)
            summarizer = "fallback"
    else:
        summarizer = "fallback"

    items = [
        {key: value for key, value in entry.items() if key != "abstract"}
        for entry in entries
    ]

    result = {
        "category": args.category,
        "source": actual_feed_url,
        "pulledAt": pulled_at,
        "summarizedAt": utc_now_iso(),
        "targetDate": target_date.isoformat(),
        "dateLabel": format_date_label(target_date),
        "paperCount": len(entries),
        "categoryCounts": category_counts,
        "digest": [clean_text(point) for point in digest_points if clean_text(point)][:5],
        "items": items,
        "status": "ready",
        "summarizer": summarizer,
    }

    write_digest(result, paths)
    print("Wrote arXiv digest:")
    for path in paths:
        print(f"- {path}")


if __name__ == "__main__":
    main()
