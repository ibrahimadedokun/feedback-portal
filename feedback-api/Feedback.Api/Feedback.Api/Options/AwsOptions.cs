using System.ComponentModel.DataAnnotations;

namespace Feedback.Api.Options;

public sealed class AwsOptions
{
    public const string SectionName = "AWS";

    [Required]
    public string Region { get; init; } = string.Empty;

    [Required]
    public string AccessKeyId { get; init; } = string.Empty;

    [Required]
    public string SecretAccessKey { get; init; } = string.Empty;
}
