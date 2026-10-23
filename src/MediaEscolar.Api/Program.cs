using System.Reflection;
using MediaEscolar.Api.Data;
using MediaEscolar.Api.Models;
using Microsoft.EntityFrameworkCore;

var builder = WebApplication.CreateBuilder(args);

// Connection string vem da configuração (variável de ambiente ConnectionStrings__Default), nunca fixa no código
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("Default")));
builder.Services.AddHealthChecks().AddDbContextCheck<AppDbContext>();

var app = builder.Build();

// Cria o schema no banco na inicialização, caso ainda não exista
using (var scope = app.Services.CreateScope())
{
    scope.ServiceProvider.GetRequiredService<AppDbContext>().Database.EnsureCreated();
}

// Versão semântica da aplicação, injetada no build da imagem (ARG VERSION do Dockerfile)
var versao = typeof(Program).Assembly
    .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "desconhecida";

app.MapHealthChecks("/health");

app.MapGet("/version", () => Results.Ok(new { versao }));

app.MapPost("/alunos", async (CadastrarAlunoRequest request, AppDbContext db) =>
{
    var aluno = new Aluno { Nome = request.Nome };
    db.Alunos.Add(aluno);
    await db.SaveChangesAsync();
    return Results.Created($"/alunos/{aluno.Id}", aluno);
});

app.MapPost("/alunos/{id:int}/notas", async (int id, RegistrarNotasRequest request, AppDbContext db) =>
{
    var aluno = await db.Alunos.FindAsync(id);
    if (aluno is null)
    {
        return Results.NotFound();
    }

    try
    {
        Calculadora.ValidarNota(request.Nota1);
        Calculadora.ValidarNota(request.Nota2);
    }
    catch (ArgumentOutOfRangeException ex)
    {
        return Results.BadRequest(new { erro = ex.Message });
    }

    aluno.Nota1 = request.Nota1;
    aluno.Nota2 = request.Nota2;
    await db.SaveChangesAsync();
    return Results.Ok(aluno);
});

app.MapGet("/alunos/{id:int}", async (int id, AppDbContext db) =>
{
    var aluno = await db.Alunos.FindAsync(id);
    if (aluno is null)
    {
        return Results.NotFound();
    }

    if (aluno.Nota1 is null || aluno.Nota2 is null)
    {
        return Results.Ok(new AlunoResponse(aluno.Id, aluno.Nome, aluno.Nota1, aluno.Nota2, null, null));
    }

    var media = Calculadora.CalcularMedia(aluno.Nota1.Value, aluno.Nota2.Value);
    var situacao = Calculadora.CalcularSituacao(media);
    return Results.Ok(new AlunoResponse(aluno.Id, aluno.Nome, aluno.Nota1, aluno.Nota2, media, situacao));
});

app.MapGet("/alunos", async (AppDbContext db) => await db.Alunos.OrderBy(a => a.Id).ToListAsync());

app.Run();

public record CadastrarAlunoRequest(string Nome);
public record RegistrarNotasRequest(double Nota1, double Nota2);
public record AlunoResponse(int Id, string Nome, double? Nota1, double? Nota2, double? Media, string? Situacao);

public partial class Program;
