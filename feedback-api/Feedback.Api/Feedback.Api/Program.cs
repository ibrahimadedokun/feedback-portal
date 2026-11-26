using Amazon;
using Amazon.Runtime;
using Amazon.SimpleNotificationService;
using Amazon.SimpleNotificationService.Model;
using Feedback.Api.Contracts;
using Feedback.Api.Options;
using Microsoft.Extensions.Options;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddOpenApi();

builder.Services
    .AddOptions<SnsOptions>()
    .Bind(builder.Configuration.GetSection(SnsOptions.SectionName))
    .ValidateDataAnnotations()
    .ValidateOnStart();

builder.Services
    .AddOptions<AwsOptions>()
    .Bind(builder.Configuration.GetSection(AwsOptions.SectionName))
    .ValidateDataAnnotations()
    .ValidateOnStart();

builder.Services.AddSingleton<IAmazonSimpleNotificationService>(sp =>
{
    var aws = sp.GetRequiredService<IOptions<AwsOptions>>().Value;

    return new AmazonSimpleNotificationServiceClient(
        new BasicAWSCredentials(aws.AccessKeyId, aws.SecretAccessKey),
        RegionEndpoint.GetBySystemName(aws.Region));
});

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

// Container Apps terminates TLS at ingress and forwards HTTP to port 8080.
// Enforce HTTPS at ingress rather than redirecting internal health probes.

app.MapGet("/health", () => Results.Ok("System is running.")).WithName("HealthCheck");

app.MapPost("/messages", async (
        PublishMessageRequest request,
        IAmazonSimpleNotificationService sns,
        IOptions<SnsOptions> options,
        CancellationToken cancellationToken) =>
    {
        if (string.IsNullOrWhiteSpace(request.Message))
        {
            return Results.ValidationProblem(new Dictionary<string, string[]>
            {
                [nameof(request.Message)] = ["Message is required."]
            });
        }

        var publishRequest = new PublishRequest
        {
            TopicArn = options.Value.TopicArn,
            Message = request.Message,
            Subject = string.IsNullOrWhiteSpace(request.Subject) ? null : request.Subject
        };

        var response = await sns.PublishAsync(publishRequest, cancellationToken);

        return Results.Ok(new PublishMessageResponse(response.MessageId));
    })
    .WithName("PublishMessage");

app.Run();
