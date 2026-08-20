"""Tests for model-agnostic message shaping in the LLM service.

The safety of a model swap (e.g. qwen3 -> gemma2) rests on `_normalize_messages`: some
chat templates reject two consecutive same-role messages, which the `chat()` path would
otherwise send. These tests pin the merge behaviour so a future edit cannot silently
reintroduce the incompatibility.
"""

from __future__ import annotations

from backend.app.services.llm import LLMService

normalize = LLMService._normalize_messages


def test_consecutive_system_messages_are_merged():
    """The chat() path sends two system messages back to back; Gemma rejects that."""
    out = normalize([
        {"role": "system", "content": "standing rules"},
        {"role": "system", "content": "the result under discussion"},
        {"role": "user", "content": "is this dangerous?"},
    ])
    assert [m["role"] for m in out] == ["system", "user"]
    assert out[0]["content"] == "standing rules\n\nthe result under discussion"
    assert out[1]["content"] == "is this dangerous?"


def test_alternating_conversation_is_unchanged():
    """Merging must be a no-op when roles already alternate."""
    messages = [
        {"role": "system", "content": "rules"},
        {"role": "user", "content": "q1"},
        {"role": "assistant", "content": "a1"},
        {"role": "user", "content": "q2"},
    ]
    out = normalize(messages)
    assert out == messages


def test_input_is_not_mutated():
    """The caller's list and dicts must be left untouched."""
    messages = [
        {"role": "system", "content": "a"},
        {"role": "system", "content": "b"},
    ]
    normalize(messages)
    assert messages == [
        {"role": "system", "content": "a"},
        {"role": "system", "content": "b"},
    ]


def test_consecutive_user_messages_are_merged():
    out = normalize([
        {"role": "user", "content": "first"},
        {"role": "user", "content": "second"},
    ])
    assert len(out) == 1
    assert out[0] == {"role": "user", "content": "first\n\nsecond"}


def test_empty_list():
    assert normalize([]) == []
