using MediaEscolar.Api.Data;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace MediaEscolar.Tests;

// Sobe a API em memória trocando o PostgreSQL por um banco EF Core InMemory, para os testes não dependerem de um banco real
public class ApiFactory : WebApplicationFactory<Program>
{
    private readonly string _nomeBanco = $"testes-{Guid.NewGuid()}";

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            var registroOriginal = services.Single(s => s.ServiceType == typeof(DbContextOptions<AppDbContext>));
            services.Remove(registroOriginal);
            services.AddDbContext<AppDbContext>(options => options.UseInMemoryDatabase(_nomeBanco));
        });
    }
}
