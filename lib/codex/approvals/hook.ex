defmodule Codex.Approvals.Hook do
  @moduledoc """
  Behaviour for implementing pluggable approval hooks.

  Hooks can provide synchronous or asynchronous approval decisions for tool invocations,
  command executions, and file access operations.

  ## Callbacks

  - `c:prepare/2` - Called before the approval review, can mutate metadata
  - `c:review_tool/3` - Review a tool invocation
  - `c:review_command/3` - Review a command execution (optional)
  - `c:review_file/3` - Review a file access operation (optional)
  - `c:await/2` - Wait for an async approval decision (optional)

  ## Return Values

  Synchronous hooks return:
  - `:allow` - approve the operation
  - `{:deny, reason}` - deny with a reason string

  Asynchronous hooks return:
  - `{:async, ref}` - defer decision, will call `c:await/2` later
  - `{:async, ref, metadata}` - defer decision with additional metadata

  ## Example

      defmodule MyApp.SlackApprovalHook do
        @behaviour Codex.Approvals.Hook

        @impl true
        def prepare(event, context) do
          # Add custom metadata before review
          {:ok, Map.put(context, :slack_channel, "#approvals")}
        end

        @impl true
        def review_tool(event, context, _opts) do
          # Post to Slack and return async ref
          ref = make_ref()
          MyApp.SlackClient.post_approval_request(ref, event, context)
          {:async, ref}
        end

        @impl true
        def await(ref, timeout) do
          # Wait for Slack response
          receive do
            {:approval_decision, ^ref, decision} -> {:ok, decision}
          after
            timeout -> {:error, :timeout}
          end
        end
      end
  """

  @type event :: map()
  @type context :: map()
  @type opts :: keyword()
  @type decision :: :allow | {:deny, String.t()}
  @type async_ref :: reference()
  @type async_result :: {:async, async_ref} | {:async, async_ref, metadata :: map()}
  @type review_result :: decision() | async_result()

  @doc """
  Called before any review operation to prepare or augment context.

  This callback can be used to add metadata, initialize state, or transform
  the context before it's passed to review callbacks.
  """
  @callback prepare(event(), context()) :: {:ok, context()} | {:error, term()}

  @doc """
  Review a tool invocation request.

  ## Parameters
  - `event` - The tool call event (contains tool_name, arguments, call_id, etc.)
  - `context` - The approval context (thread, metadata, etc.)
  - `opts` - Hook-specific options

  ## Returns
  - `:allow` - approve the tool invocation
  - `{:deny, reason}` - deny with a reason
  - `{:async, ref}` - defer decision, will be awaited later
  - `{:async, ref, metadata}` - defer with additional metadata
  """
  @callback review_tool(event(), context(), opts()) :: review_result()

  @doc """
  Review a command execution request (optional).

  If not implemented, commands are allowed by default.
  """
  @callback review_command(event(), context(), opts()) :: review_result()

  @doc """
  Review a file access request (optional).

  If not implemented, file operations are allowed by default.
  """
  @callback review_file(event(), context(), opts()) :: review_result()

  @doc """
  Wait for an async approval decision.

  This callback is called when a review returned `{:async, ref}` and the
  system needs to wait for the decision.

  ## Parameters
  - `ref` - The reference returned by the review callback
  - `timeout` - Maximum time to wait in milliseconds

  ## Returns
  - `{:ok, decision}` - the approval decision
  - `{:error, :timeout}` - timeout reached
  - `{:error, reason}` - other error
  """
  @callback await(async_ref(), timeout :: pos_integer()) ::
              {:ok, decision()} | {:error, :timeout | term()}

  @optional_callbacks prepare: 2, review_command: 3, review_file: 3, await: 2

  @doc """
  Default prepare implementation that returns the context unchanged.
  """
  def default_prepare(_event, context), do: {:ok, context}

  @doc """
  Default review implementation that allows all operations.
  """
  def default_review(_event, _context, _opts), do: :allow
end
