using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Xunit;

namespace MediaEscolar.Tests;

// Teste de integração da API: sobe a aplicação em memória (WebApplicationFactory) e exercita os endpoints reais via HTTP
public class ApiIntegrationTests : IClassFixture<ApiFactory>
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private readonly HttpClient _client;

    public ApiIntegrationTests(ApiFactory factory)
    {
        _client = factory.CreateClient();
    }

    // Teste de API: cobre o fluxo completo end-to-end (cadastrar aluno -> registrar notas -> consultar) validando média e situação calculadas pelo servidor
    [Fact]
    public async Task FluxoCompleto_CadastrarRegistrarNotasEConsultar_DeveRetornarMediaESituacaoCorretas()
    {
        // Cadastra um novo aluno e espera status 201 (Created)
        var cadastroResponse = await _client.PostAsJsonAsync("/alunos", new { nome = "Maria" }, JsonOptions);
        Assert.Equal(HttpStatusCode.Created, cadastroResponse.StatusCode);

        var alunoCriado = await cadastroResponse.Content.ReadFromJsonAsync<AlunoCriadoDto>(JsonOptions);
        Assert.NotNull(alunoCriado);

        // Registra as duas notas do aluno cadastrado e espera status 200 (OK)
        var notasResponse = await _client.PostAsJsonAsync(
            $"/alunos/{alunoCriado!.Id}/notas", new { nota1 = 8.0, nota2 = 6.0 }, JsonOptions);
        Assert.Equal(HttpStatusCode.OK, notasResponse.StatusCode);

        // Consulta o aluno e verifica se a média e a situação foram calculadas corretamente pela API
        var consultaResponse = await _client.GetAsync($"/alunos/{alunoCriado.Id}");
        Assert.Equal(HttpStatusCode.OK, consultaResponse.StatusCode);

        var alunoConsultado = await consultaResponse.Content.ReadFromJsonAsync<AlunoConsultadoDto>(JsonOptions);
        Assert.NotNull(alunoConsultado);
        Assert.Equal(7.0, alunoConsultado!.Media);
        Assert.Equal("Aprovado", alunoConsultado.Situacao);
    }

    // Teste de API: o health check (usado pelo Docker, compose e smoke test do deploy) deve responder Healthy
    [Fact]
    public async Task Health_DeveRetornarHealthy()
    {
        var response = await _client.GetAsync("/health");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("Healthy", await response.Content.ReadAsStringAsync());
    }

    // Teste de API: /version deve expor a versão semântica da aplicação (usada para confirmar qual release está no ar)
    [Fact]
    public async Task Version_DeveRetornarVersaoSemantica()
    {
        var versao = await _client.GetFromJsonAsync<VersaoDto>("/version", JsonOptions);
        Assert.NotNull(versao);
        Assert.Matches(@"^\d+\.\d+\.\d+", versao!.Versao);
    }

    private record VersaoDto(string Versao);
    private record AlunoCriadoDto(int Id, string Nome, double? Nota1, double? Nota2);
    private record AlunoConsultadoDto(int Id, string Nome, double? Nota1, double? Nota2, double? Media, string? Situacao);
}
