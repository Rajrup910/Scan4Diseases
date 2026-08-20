using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;

var builder = WebApplication.CreateBuilder(args);

// The gateway does NOT issue tokens. FastAPI stays the identity provider; here we only
// re-validate the token it signed. Same secret => same HS256 signature check.
var jwtSecret = Environment.GetEnvironmentVariable("JWT_SECRET")
    ?? throw new InvalidOperationException(
        "JWT_SECRET is not set. Export the SAME value the backend .env uses.");

// Forward every request to FastAPI (see appsettings.json).
builder.Services.AddReverseProxy()
    .LoadFromConfig(builder.Configuration.GetSection("ReverseProxy"));

// Validate the backend's JWT exactly the way it was minted: HS256, no issuer/audience
// (the Python token carries neither), honour expiry.
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSecret)),
            ValidateIssuer = false,
            ValidateAudience = false,
            ValidateLifetime = true,
            ClockSkew = TimeSpan.FromSeconds(30),
        };
    });

builder.Services.AddAuthorization();

var app = builder.Build();

app.UseAuthentication();
app.UseAuthorization();

// Routes tagged with AuthorizationPolicy "default" require a valid token; the rest are open.
app.MapReverseProxy();

app.Run();
