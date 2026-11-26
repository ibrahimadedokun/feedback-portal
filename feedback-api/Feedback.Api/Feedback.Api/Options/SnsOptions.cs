using System.ComponentModel.DataAnnotations;

namespace Feedback.Api.Options;

public sealed class SnsOptions
{
    public const string SectionName = "Sns";

    [Required]
    public string TopicArn { get; init; } = string.Empty;
}
