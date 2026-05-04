#!/usr/bin/env python
from __future__ import annotations

import argparse
import io
import json
import re
import shutil
import zipfile
from collections import Counter
from pathlib import Path
from typing import Any, Iterable


DEFAULT_INPUT_ZIP = "data_tmp/crosswoz_master_2.zip"
DEFAULT_OUTPUT = "datasets_tmp/crosswoz_base_chat_clean_v1"
DEFAULT_SPLITS = ["train", "val"]

USER_REJECT_PATTERNS: dict[str, re.Pattern[str]] = {
    "greeting_only": re.compile(
        r"^(你好|您好|嗨|hello|hi)[！!。,.， ]*$", re.IGNORECASE
    ),
    "confirm_only": re.compile(
        r"^(好的|行|可以|嗯|好吧|那就这样|谢谢|谢了)[！!。,.， ]*$", re.IGNORECASE
    ),
    "multi_choice_or_exam": re.compile(
        r"选择题|单选题|多选题|填空题|判断题|ABCD|A\.|B\.|C\.|D\.|正确答案|"
        r"请问.*哪个选项|下列.*的是",
        re.IGNORECASE,
    ),
    "translation_or_rewrite": re.compile(
        r"翻译|改写|润色|总结|概括|续写|扩写|缩写|生成文案|写一篇|写作文|"
        r"帮我修改|重写|同义句",
        re.IGNORECASE,
    ),
    "medical_or_legal_or_finance": re.compile(
        r"医保|医院|医生|症状|药|治疗|法律|律师|赔偿|贷款|理财|股票|基金|保险",
        re.IGNORECASE,
    ),
    "meta_task": re.compile(
        r"你能帮我|请帮我推荐|帮我安排行程|帮我规划|告诉我怎么去|帮我预订",
        re.IGNORECASE,
    ),
}

ASSISTANT_REJECT_PATTERNS: dict[str, re.Pattern[str]] = {
    "too_slot_listy": re.compile(
        r"推荐您选择|为您推荐|您可以选择|电话是|地址是|人均消费|门票|评分|营业时间|酒店设施|"
        r"推荐菜|周边景点|周边餐馆|周边酒店"
    ),
    "service_closure": re.compile(
        r"祝您|旅途愉快|玩的开心|还有什么可以帮您", re.IGNORECASE
    ),
    "code_or_markdown": re.compile(r"```|^\s*(def |class |SELECT )", re.IGNORECASE),
}

DOMAIN_BLACKLIST = {"地铁", "出租", "taxi", "metro"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Export strict CrossWOZ base-chat subset"
    )
    parser.add_argument("--input-zip", default=DEFAULT_INPUT_ZIP)
    parser.add_argument("--output-root", default=DEFAULT_OUTPUT)
    parser.add_argument("--cluster-name", default="base_chat")
    parser.add_argument("--expert-id", type=int, default=0)
    parser.add_argument("--splits", nargs="*", default=DEFAULT_SPLITS)
    parser.add_argument("--max-samples", type=int, default=1800)
    parser.add_argument("--user-min-chars", type=int, default=8)
    parser.add_argument("--user-max-chars", type=int, default=80)
    parser.add_argument("--assistant-min-chars", type=int, default=12)
    parser.add_argument("--assistant-max-chars", type=int, default=96)
    parser.add_argument("--max-newlines", type=int, default=1)
    parser.add_argument("--min-response-words", type=int, default=4)
    parser.add_argument("--max-response-words", type=int, default=30)
    parser.add_argument("--reset-output", action="store_true")
    return parser.parse_args()


def normalize_space(text: str) -> str:
    text = text.replace("\r\n", "\n").replace("\r", "\n").strip()
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n+", "\n", text)
    return text.strip()


def count_cjk(text: str) -> int:
    return sum(1 for ch in text if "\u4e00" <= ch <= "\u9fff")


def build_training_text(user: str, assistant: str) -> str:
    return f"User: {user}\nAssistant: {assistant}"


def ensure_empty_dir(path: Path, reset: bool) -> None:
    if path.exists() and reset:
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)


def write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")


def extract_domain(dialog: dict[str, Any]) -> str:
    raw_type = str(dialog.get("type", ""))
    return normalize_space(raw_type)


def iter_split_dialogs(
    input_zip: Path, split: str
) -> Iterable[tuple[str, dict[str, Any]]]:
    outer_name = f"CrossWOZ-master/data/crosswoz/{split}.json.zip"
    inner_name = f"{split}.json"
    with zipfile.ZipFile(input_zip) as outer:
        with zipfile.ZipFile(io.BytesIO(outer.read(outer_name))) as inner:
            payload = json.loads(inner.read(inner_name).decode("utf-8"))
    for dialog_id, dialog in payload.items():
        yield str(dialog_id), dialog


def reject_reason(
    user: str,
    assistant: str,
    domain: str,
    dialog_id: str,
    turn_index: int,
    args: argparse.Namespace,
) -> str | None:
    if domain in DOMAIN_BLACKLIST:
        return "blacklisted_domain"
    if turn_index > 8:
        return "late_turn"
    if count_cjk(user) < 4 or count_cjk(assistant) < 6:
        return "low_chinese_content"
    if len(user) < args.user_min_chars:
        return "user_too_short"
    if len(user) > args.user_max_chars:
        return "user_too_long"
    if len(assistant) < args.assistant_min_chars:
        return "assistant_too_short"
    if len(assistant) > args.assistant_max_chars:
        return "assistant_too_long"
    if (user + "\n" + assistant).count("\n") > args.max_newlines:
        return "too_many_newlines"
    if len(assistant.split()) < args.min_response_words:
        return "assistant_too_few_words"
    if len(assistant.split()) > args.max_response_words:
        return "assistant_too_many_words"
    if len(assistant) > max(len(user) * 3, 96):
        return "answer_ratio_too_high"
    if len(user) <= 24 and len(assistant) > max(int(len(user) * 2.2), 72):
        return "assistant_overexpanded_short_prompt"
    if re.search(
        r"\d{3,}|[0-9]{2,}[:：][0-9]{2,}|[0-9]{3,}-[0-9]{5,}", user + " " + assistant
    ):
        return "number_heavy_slot_value"
    for reason, pattern in USER_REJECT_PATTERNS.items():
        if pattern.search(user):
            return reason
    for reason, pattern in ASSISTANT_REJECT_PATTERNS.items():
        if pattern.search(assistant):
            return reason
    if dialog_id.startswith("0"):
        pass
    return None


def main() -> int:
    args = parse_args()
    input_zip = Path(args.input_zip)
    if not input_zip.exists():
        raise FileNotFoundError(f"Input zip not found: {input_zip}")

    output_root = Path(args.output_root)
    ensure_empty_dir(output_root, reset=args.reset_output)

    data_path = (
        output_root
        / "data"
        / args.cluster_name
        / f"expert_{args.expert_id}"
        / "samples.jsonl"
    )
    meta_path = (
        output_root
        / "metadata"
        / args.cluster_name
        / f"expert_{args.expert_id}"
        / "routing_meta.jsonl"
    )

    kept_rows: list[dict[str, Any]] = []
    meta_rows: list[dict[str, Any]] = []
    previews: list[dict[str, Any]] = []
    rejection_counts: Counter[str] = Counter()
    split_counts: Counter[str] = Counter()
    domain_counts: Counter[str] = Counter()
    seen_pairs: set[tuple[str, str]] = set()

    for split in args.splits:
        for dialog_id, dialog in iter_split_dialogs(input_zip, split):
            domain = extract_domain(dialog)
            messages = dialog.get("messages", [])
            if not isinstance(messages, list) or len(messages) < 2:
                rejection_counts["bad_messages"] += 1
                continue

            for idx in range(len(messages) - 1):
                current = messages[idx]
                nxt = messages[idx + 1]
                if current.get("role") != "usr" or nxt.get("role") != "sys":
                    continue
                user = normalize_space(str(current.get("content", "")))
                assistant = normalize_space(str(nxt.get("content", "")))
                if not user or not assistant:
                    rejection_counts["empty_turn"] += 1
                    continue
                reason = reject_reason(
                    user, assistant, domain, dialog_id, idx // 2, args
                )
                if reason:
                    rejection_counts[reason] += 1
                    continue
                key = (user.lower(), assistant.lower())
                if key in seen_pairs:
                    rejection_counts["duplicate_pair"] += 1
                    continue
                seen_pairs.add(key)

                pair_id = f"crosswoz_{split}_{len(kept_rows) + 1:07d}"
                kept_rows.append(
                    {
                        "id": pair_id,
                        "category": "crosswoz_task_dialogue",
                        "text": build_training_text(user, assistant),
                        "conversation": [{"human": user, "assistant": assistant}],
                    }
                )
                meta_rows.append(
                    {
                        "id": pair_id,
                        "source": "CrossWOZ",
                        "split": split,
                        "dialog_id": dialog_id,
                        "turn_index": idx,
                        "domain": domain,
                        "cluster": args.cluster_name,
                        "expert_id": args.expert_id,
                        "user_chars": len(user),
                        "assistant_chars": len(assistant),
                    }
                )
                split_counts[split] += 1
                domain_counts[domain] += 1
                if len(previews) < 12:
                    previews.append(
                        {
                            "id": pair_id,
                            "split": split,
                            "dialog_id": dialog_id,
                            "domain": domain,
                            "user": user,
                            "assistant": assistant,
                            "user_chars": len(user),
                            "assistant_chars": len(assistant),
                        }
                    )
                if len(kept_rows) >= args.max_samples:
                    break
            if len(kept_rows) >= args.max_samples:
                break
        if len(kept_rows) >= args.max_samples:
            break

    write_jsonl(data_path, kept_rows)
    write_jsonl(meta_path, meta_rows)

    summary = {
        "input_zip": str(input_zip).replace("/", "\\"),
        "output_root": str(output_root).replace("/", "\\"),
        "kept": len(kept_rows),
        "splits": args.splits,
        "split_counts": dict(split_counts),
        "domain_counts": dict(domain_counts),
        "rejection_counts": dict(rejection_counts.most_common()),
        "preview": previews,
    }
    (output_root / "split_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    safe_output = str(output_root).replace("/", "\\")
    print(f"[done] kept={len(kept_rows)} output={safe_output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
