using MediaEscolar.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace MediaEscolar.Api.Data;

// Contexto do EF Core: mapeia a entidade Aluno para a tabela "alunos" no PostgreSQL
public class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<Aluno> Alunos => Set<Aluno>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Aluno>(aluno =>
        {
            aluno.ToTable("alunos");
            aluno.HasKey(a => a.Id);
            aluno.Property(a => a.Nome).HasMaxLength(200).IsRequired();
        });
    }
}
