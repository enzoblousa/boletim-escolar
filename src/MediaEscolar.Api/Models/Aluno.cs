namespace MediaEscolar.Api.Models;

public class Aluno
{
    public int Id { get; set; }
    public string Nome { get; set; } = string.Empty;
    public double? Nota1 { get; set; }
    public double? Nota2 { get; set; }
}
