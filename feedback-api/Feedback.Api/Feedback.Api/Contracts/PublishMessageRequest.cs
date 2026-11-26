namespace Feedback.Api.Contracts;

public sealed record PublishMessageRequest(string Message, string? Subject);

public sealed record PublishMessageResponse(string MessageId);
