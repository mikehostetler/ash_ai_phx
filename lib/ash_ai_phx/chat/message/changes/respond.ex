defmodule AshAiPhx.Chat.Message.Changes.Respond do
  use Ash.Resource.Change
  require Ash.Query

  alias ReqLLM.Context

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_transaction(changeset, fn changeset ->
      message = changeset.data

      messages =
        AshAiPhx.Chat.Message
        |> Ash.Query.filter(conversation_id == ^message.conversation_id)
        |> Ash.Query.filter(id != ^message.id)
        |> Ash.Query.select([:text, :source, :tool_calls, :tool_results])
        |> Ash.Query.sort(inserted_at: :asc)
        |> Ash.read!()
        |> Enum.concat([%{source: :user, text: message.text}])

      prompt_messages =
        [
          Context.system("""
          You are a helpful chat bot.
          Your job is to use the tools at your disposal to assist the user.
          """)
        ] ++ message_chain(messages)

      new_message_id = Ash.UUIDv7.generate()

      final_state =
        prompt_messages
        |> AshAi.ToolLoop.stream(
          otp_app: :ash_ai_phx,
          tools: true,
          model: "openai:gpt-4o",
          actor: context.actor,
          tenant: context.tenant,
          context: Map.new(Ash.Context.to_opts(context))
        )
        |> Enum.reduce(%{text: "", tool_calls: [], tool_results: []}, fn
          {:content, content}, acc ->
            if content not in [nil, ""] do
              AshAiPhx.Chat.Message
              |> Ash.Changeset.for_create(
                :upsert_response,
                %{
                  id: new_message_id,
                  response_to_id: message.id,
                  conversation_id: message.conversation_id,
                  text: content
                },
                actor: %AshAi{}
              )
              |> Ash.create!()
            end

            %{acc | text: acc.text <> (content || "")}

          {:tool_call, tool_call}, acc ->
            %{acc | tool_calls: append_event(acc.tool_calls, tool_call)}

          {:tool_result, %{id: id, result: result}}, acc ->
            %{
              acc
              | tool_results: append_event(acc.tool_results, normalize_tool_result(id, result))
            }

          {:done, _}, acc ->
            acc

          _, acc ->
            acc
        end)

      final_text =
        if String.trim(final_state.text || "") == "" &&
             (final_state.tool_calls != [] || final_state.tool_results != []) do
          "Completed tool call."
        else
          final_state.text
        end

      if final_state.tool_calls != [] || final_state.tool_results != [] || final_text != "" do
        AshAiPhx.Chat.Message
        |> Ash.Changeset.for_create(
          :upsert_response,
          %{
            id: new_message_id,
            response_to_id: message.id,
            conversation_id: message.conversation_id,
            complete: true,
            tool_calls: final_state.tool_calls,
            tool_results: final_state.tool_results,
            text: final_text
          },
          actor: %AshAi{}
        )
        |> Ash.create!()
      end

      changeset
    end)
  end

  defp message_chain(messages) do
    Enum.flat_map(messages, fn
      %{source: :agent} = message ->
        assistant =
          Context.assistant(
            message.text || "",
            tool_calls: normalize_tool_calls(message.tool_calls || [])
          )

        tool_results =
          message.tool_results
          |> List.wrap()
          |> Enum.flat_map(fn result ->
            case normalize_tool_result_message(result) do
              nil -> []
              message -> [message]
            end
          end)

        [assistant | tool_results]

      %{source: :user, text: text} ->
        [Context.user(text || "")]
    end)
  end

  defp normalize_tool_calls(tool_calls) do
    Enum.flat_map(List.wrap(tool_calls), fn call ->
      normalized = %{
        id:
          call["id"] || call[:id] || call["call_id"] || call[:call_id] ||
            "call_\387426",
        name: call["name"] || call[:name],
        arguments: call["arguments"] || call[:arguments] || %{}
      }

      if is_binary(normalized.name), do: [normalized], else: []
    end)
  end

  defp append_event(items, value) when is_list(items), do: items ++ [value]
  defp append_event(_items, value), do: [value]

  defp normalize_tool_result_message(result) do
    id =
      result["tool_call_id"] || result[:tool_call_id] || result["id"] || result[:id]

    content = result["content"] || result[:content]

    if is_binary(id) do
      Context.tool_result(id, content || "")
    else
      nil
    end
  end

  defp normalize_tool_result(tool_call_id, {:ok, content, _raw}) do
    %{
      tool_call_id: tool_call_id,
      content: content,
      is_error: false
    }
  end

  defp normalize_tool_result(tool_call_id, {:error, content}) do
    %{
      tool_call_id: tool_call_id,
      content: content,
      is_error: true
    }
  end
end
