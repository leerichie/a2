# a2 health-history import format

Every imported observation is staged before it reaches the user's live diary.

```json
{
  "source": {
    "type": "chatgpt_shared_conversation",
    "external_id": "share-id",
    "title": "Conversation title",
    "retrieved_at": "ISO-8601 timestamp"
  },
  "records": [
    {
      "kind": "meal | activity | measurement",
      "occurred_at": null,
      "reported_date_text": "today",
      "values": {},
      "confidence": "high | medium | low",
      "evidence": "label | user_report | assistant_estimate",
      "source_message_id": "original-message-id",
      "review_status": "pending"
    }
  ]
}
```

## Import rules

- Preserve the user's original statement separately from derived values.
- Prefer explicit package labels over assistant estimates.
- Do not turn relative dates into calendar dates without reliable conversation timestamps.
- Do not import advice, hypothetical menus, or recommended meals as consumed meals.
- Deduplicate by source message ID first, then by user, time, type, and content fingerprint.
- Keep uncertain records in staging until the user approves or edits them.
- Shared links are ingestion sources, not permanent synchronisation channels.
