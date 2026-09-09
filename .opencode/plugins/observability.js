const MAX_RESULT_LENGTH = 4000

export const ObservabilityPlugin = async ({ client, directory, worktree }) => {
  const root = worktree || directory
  const bridge = `${root}/hooks/opencode_bridge.py`

  const logFailure = async (message, error) => {
    const detail = error instanceof Error ? error.message : String(error)
    console.error(`[opencode-observability] ${message}: ${detail}`)
    try {
      await client.app.log({
        body: {
          service: "commandline-crew-observability",
          level: "error",
          message: `${message}: ${detail}`,
        },
      })
    } catch {
      // Logging must never turn an observability failure into an OpenCode failure.
    }
  }

  const send = async (kind, fields = {}) => {
    const candidates = process.env.OPENCODE_HOOKS_PYTHON
      ? [[process.env.OPENCODE_HOOKS_PYTHON]]
      : process.platform === "win32"
        ? [["python"], ["py", "-3"], ["python3"]]
        : [["python3"], ["python"]]
    const failures = []

    for (const candidate of candidates) {
      try {
        const child = Bun.spawn(
          [...candidate, bridge],
          {
            cwd: root,
            stdin: JSON.stringify({
              kind,
              cwd: root,
              ...fields,
              timestamp: Number.isInteger(fields.timestamp) ? fields.timestamp : Date.now(),
            }),
            stdout: "ignore",
            stderr: "pipe",
          },
        )
        const exitCode = await child.exited
        if (exitCode === 0) {
          return
        }
        const stderr = await new Response(child.stderr).text()
        failures.push(`${candidate.join(" ")} exited ${exitCode}: ${stderr.trim()}`)
      } catch (error) {
        const detail = error instanceof Error ? error.message : String(error)
        failures.push(`${candidate.join(" ")} failed: ${detail}`)
      }
    }

    await logFailure("bridge invocation failed", failures.join("; "))
  }

  return {
    event: async ({ event }) => {
      try {
        const properties = event?.properties || {}
        if (event?.type === "session.created") {
          const info = properties.info || {}
          await send("session_start", {
            session_id: info.id,
            timestamp: info.time?.created,
            source: "opencode",
          })
        } else if (event?.type === "session.idle") {
          await send("session_end", {
            session_id: properties.sessionID,
            reason: "idle",
          })
        } else if (event?.type === "session.deleted") {
          const info = properties.info || {}
          await send("session_end", {
            session_id: info.id,
            timestamp: info.time?.updated,
            reason: "deleted",
          })
        } else if (event?.type === "session.error") {
          const error = properties.error || {}
          await send("error", {
            session_id: properties.sessionID,
            error_name: error.name,
            error_message: error.data?.message,
          })
        } else if (
          event?.type === "message.updated" &&
          properties.info?.role === "assistant" &&
          properties.info?.error
        ) {
          const error = properties.info.error
          await send("error", {
            session_id: properties.info.sessionID,
            timestamp: properties.info.time?.completed || properties.info.time?.created,
            error_name: error.name,
            error_message: error.data?.message,
          })
        } else if (
          event?.type === "message.part.updated" &&
          properties.part?.type === "tool" &&
          properties.part?.state?.status === "error"
        ) {
          const part = properties.part
          await send("post_tool", {
            session_id: part.sessionID,
            timestamp: part.state.time?.end,
            tool_name: part.tool,
            tool_args: part.state.input,
            result_type: "failure",
            result_text: part.state.error,
          })
        }
      } catch (error) {
        await logFailure(`event ${event?.type || "unknown"} failed`, error)
      }
    },

    "chat.message": async (input, output) => {
      try {
        const prompt = (output?.parts || [])
          .filter((part) => part?.type === "text" && typeof part.text === "string")
          .map((part) => part.text)
          .join("\n")
        if (prompt) {
          await send("prompt", {
            session_id: input?.sessionID,
            timestamp: output?.message?.time?.created,
            prompt,
          })
        }
      } catch (error) {
        await logFailure("chat.message failed", error)
      }
    },

    "tool.execute.before": async (input, output) => {
      await send("pre_tool", {
        session_id: input?.sessionID,
        tool_name: input?.tool,
        tool_args: output?.args,
      })
    },

    "tool.execute.after": async (input, output) => {
      await send("post_tool", {
        session_id: input?.sessionID,
        tool_name: input?.tool,
        tool_args: input?.args,
        result_type: "success",
        result_text: typeof output?.output === "string"
          ? output.output.slice(0, MAX_RESULT_LENGTH)
          : "",
      })
    },
  }
}
