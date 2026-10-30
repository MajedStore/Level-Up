// Level Up — Based on Streak by InlitX. GPL-3.0-only.
export class ApiError extends Error {
  constructor(status, code, message, extra = {}) {
    super(message);
    this.status = status;
    this.code = code;
    this.extra = extra;
  }
}
export const invalid = (message, code = "invalid_transition") => {
  throw new ApiError(422, code, message);
};
export function requireRule(condition, message, code) {
  if (!condition) invalid(message, code);
}
