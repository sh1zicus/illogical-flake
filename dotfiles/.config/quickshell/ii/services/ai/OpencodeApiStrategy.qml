import QtQuick

// Strategy that calls the local `opencode` CLI instead of a HTTP API.
// It runs `opencode run --format json`, feeds it the last user message, and
// continues the same OpenCode session (via `-s <sessionID>`) across requests.
// The model is passed through `model.model` (provider/model format) and the
// agent through Persistent.states.ai.agent (defaults to "plan", the read-only
// built-in; switch to "build" to let the agent edit files and run commands).
ApiStrategy {
    property bool isReasoning: false

    // The session we keep reusing for multi-turn conversations.
    property string currentSessionID: ""

    // Data captured in buildRequestData, consumed by finalizeScriptContent.
    property string pendingPrompt: ""
    property string pendingFilePath: ""
    property string pendingModel: ""
    property string pendingAgent: "plan"

    // Last token usage reported by step_finish (returned in onRequestFinished).
    property var lastTokenUsage: ({})

    function buildEndpoint(model: AiModel): string {
        return ""; // No HTTP endpoint; finalizeScriptContent replaces the whole script.
    }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePath: string) {
        // OpenCode keeps its own conversation history server-side, so we only
        // need to forward the newest user message.
        root.pendingPrompt = "";
        if (messages.length > 0) {
            const lastUser = messages[messages.length - 1];
            if (lastUser.role === "user") {
                root.pendingPrompt = lastUser.rawContent;
            }
        }

        root.pendingFilePath = filePath ?? "";
        root.pendingModel = model.model;
        root.pendingAgent = Persistent.states?.ai?.agent || "plan";

        // Signal a fresh conversation (e.g. after /clear) by resetting the
        // session if the history only contains the new user message.
        const onlyNewMessage = messages.length === 1;
        if (onlyNewMessage) {
            root.currentSessionID = "";
        }

        return {};
    }

    function buildAuthorizationHeader(apiKeyEnvVarName: string): string {
        return ""; // No auth header needed.
    }

    // Replace the generated curl script with an `opencode run` invocation.
    function finalizeScriptContent(scriptContent: string): string {
        const marker = `QS_AI_MSG_${Date.now().toString(36)}`;

        // The prompt goes into a quoted heredoc so no bash expansion happens.
        let script = "#!/usr/bin/env bash\n";
        script += `MESSAGE="$(cat <<'${marker}'\n`;
        script += `${root.pendingPrompt}\n`;
        script += `${marker}\n")\n`;

        let cmd = "opencode run --format json --thinking";
        cmd += ` --agent ${root.pendingAgent}`;
        if (root.pendingModel && root.pendingModel.length > 0) {
            cmd += ` -m '${root.pendingModel}'`;
        }
        if (root.currentSessionID && root.currentSessionID.length > 0) {
            cmd += ` -s '${root.currentSessionID}'`;
        }
        if (root.pendingFilePath && root.pendingFilePath.length > 0) {
            cmd += ` -f '${root.pendingFilePath}'`;
        }
        cmd += ' "$MESSAGE"\n';

        script += cmd;
        return script;
    }

    function parseResponseLine(line, message) {
        const cleanData = line.trim();
        if (!cleanData) return {};

        try {
            const dataJson = JSON.parse(cleanData);

            // Track the session for later continuation.
            if (dataJson.type === "step_start") {
                if (dataJson.sessionID) root.currentSessionID = dataJson.sessionID;
                return {};
            }

            // Error-ish events: mark finished and surface the message.
            if (dataJson.type === "error" || dataJson.part?.type === "error") {
                const errorText = dataJson.error?.message
                    ?? dataJson.part?.error
                    ?? JSON.stringify(dataJson);
                const errorMsg = `**Error**: ${errorText}`;
                message.rawContent += errorMsg;
                message.content += errorMsg;
                return { finished: true };
            }

            let newContent = "";

            // Reasoning events (thinking blocks).
            if (dataJson.type === "reasoning" && dataJson.part?.text?.length > 0) {
                if (!isReasoning) {
                    isReasoning = true;
                    const startBlock = "\n\n thinking\n\n";
                    message.rawContent += startBlock;
                    message.content += startBlock;
                }
                newContent = dataJson.part.text;
            }

            // Normal text output.
            if (dataJson.type === "text" && dataJson.part?.text?.length > 0) {
                if (isReasoning) {
                    isReasoning = false;
                    const endBlock = "\n\n response\n\n";
                    message.rawContent += endBlock;
                    message.content += endBlock;
                }
                newContent = dataJson.part.text;
            }

            // Tool usage (e.g. bash/edit the model performed). Surface them as commands.
            if (dataJson.type === "tool_use" && dataJson.part?.type === "tool") {
                const toolName = dataJson.part.tool || "tool";
                const input = dataJson.part.state?.input?.command
                    ?? dataJson.part.state?.input?.filePath
                    ?? "";
                const toolLabel = `${toolName}${input ? ": " + input : ""}`;
                const toolLine = `\n\n command\n${toolLabel}\n response`;
                message.rawContent += toolLine;
                message.content += toolLine;
            }

            message.content += newContent;
            message.rawContent += newContent;

            // Token accounting from step finishes.
            if (dataJson.type === "step_finish" && dataJson.part?.tokens) {
                const tokens = dataJson.part.tokens;
                root.lastTokenUsage = {
                    input: tokens.input ?? -1,
                    output: tokens.output ?? -1,
                    total: tokens.total ?? -1,
                };
            }

        } catch (e) {
            // Not JSON (e.g. a non-JSON log line): fall back to raw passthrough.
            console.log("[AI] OpenCode: Could not parse line: ", e);
            message.rawContent += line;
            message.content += line;
        }

        return {};
    }

    function onRequestFinished(message) {
        // The process exiting means the assistant finished its turn.
        return {
            finished: !message.done,
            tokenUsage: root.lastTokenUsage,
        };
    }

    function reset() {
        // Do NOT clear currentSessionID here: reset() runs at the start of
        // every request and the OpenCode session must survive across turns.
        isReasoning = false;
        root.lastTokenUsage = {};
    }

    // Called from Ai.clearMessages() to start a brand new OpenCode session.
    function resetSession() {
        root.currentSessionID = "";
        root.lastTokenUsage = {};
    }
}