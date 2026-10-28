const agentModes = ['assist', 'authorized', 'full_access'];
const defaultAgentMode = 'assist';
const defaultAgentHostMode = 'full_access';

/// Legacy review and unknown values use assist; no database migration is needed.
String normalizeAgentMode(String? mode) =>
    agentModes.contains(mode) ? mode! : defaultAgentMode;
