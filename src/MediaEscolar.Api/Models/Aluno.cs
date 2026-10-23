namespace MediaEscolar.Api.Models;

public class Aluno
{
    public int Id { get; set; }
    public string Nome { get; set; } = string.Empty;
    public double? Nota1 { get; set; }
    public double? Nota2 { get; set; }
    // SIMULAÇÃO A2 (release defeituosa proposital): coluna nova sem migration.
    // Testes (InMemory) e CI (banco novo) passam, mas num banco que já existe o EnsureCreated não cria a coluna -> erro 500.
    public string? Email { get; set; }
}
