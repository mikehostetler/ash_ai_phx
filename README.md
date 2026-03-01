# AshAiPhx

This repository is a public generated-output sample for reviewing
[ash-project/ash_ai PR #177](https://github.com/ash-project/ash_ai/pull/177).
It exists specifically so reviewers can inspect real generator output produced by the current branch.

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Copy `.env.example` to `.env` and set `OPENAI_API_KEY`
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Smoke test prompts

Use these in order; they reliably trigger multi-tool behavior in the generated chat UI.

### Baseline 2-tool chain

```text
You must call tools before answering.
First call chat_list_conversations with {"limit": 1}.
Then call chat_message_history using the returned conversation_id.
After both tool results, return exactly 2 sentences summarizing that conversation.
```

### 3+ tool calls (fan-out)

```text
Call chat_list_conversations with {"limit": 2}.
Then call chat_message_history once for each returned conversation_id.
After both histories, compare them in 3 bullet points.
Do not answer until all tool calls complete.
```

### Repeated tool call (good for regression)

```text
Use tools only.
Step 1: call chat_list_conversations with {"limit": 1}.
Step 2: call chat_message_history for that conversation_id with {"limit": 100, "sort":[{"field":"id","direction":"asc"}]}.
Step 3: call chat_message_history again for the same conversation_id with {"limit": 1, "sort":[{"field":"id","direction":"desc"}]}.
Then report oldest and latest message text.
```

### Error + recovery path

```text
First call chat_message_history with conversation_id "00000000-0000-0000-0000-000000000000".
Then recover by calling chat_list_conversations {"limit": 1} and chat_message_history for that real id.
Return one sentence describing the failure and successful recovery.
```

### Quick pass criteria

* You see `tool:` lines for each invoked tool and corresponding `tool_result` lines.
* Responses complete without browser console `Stream error` messages.
* Multi-step prompts complete in a single reply after tool execution.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
