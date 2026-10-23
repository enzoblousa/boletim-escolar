#Dockerfile multi-stage, um roda o sdk inteiro o outro apenas o runtime do dotnet ASP (versão alpine, bem menor)

#faça um pull da imagem do dotnet sdk(compilador, nugetpackages, dotnet publish etc) e nomeia de build para reuso
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
#define o diretório /src como diretório de trabalho, "entra nele"
WORKDIR /src

#OTIMIZAÇÃO DE CACHE: copia primeiro só os arquivos que definem dependências (sln, global.json e csproj) e roda o restore.
#enquanto essas dependências não mudarem, o docker reaproveita essa camada e não baixa os pacotes NuGet de novo a cada mudança no código
COPY MediaEscolar.sln global.json ./
COPY src/MediaEscolar.Api/MediaEscolar.Api.csproj src/MediaEscolar.Api/
COPY tests/MediaEscolar.Tests/MediaEscolar.Tests.csproj tests/MediaEscolar.Tests/
RUN dotnet restore src/MediaEscolar.Api/MediaEscolar.Api.csproj

#só agora copia o código-fonte (essa camada muda a cada commit, as de cima não)
COPY src/ src/

#versão semântica injetada pelo pipeline (tag git v1.2.3 -> VERSION=1.2.3); se não for passada, usa a <Version> do csproj
ARG VERSION
#compila e publica apenas o projeto da api em modo release, sem restaurar de novo e sem gerar o executável nativo (só a dll é necessária)
RUN dotnet publish src/MediaEscolar.Api/MediaEscolar.Api.csproj -c Release -o /app --no-restore \
    -p:UseAppHost=false ${VERSION:+-p:Version=$VERSION}


#imagem final, runtime alpine(apenas o necessário para rodar uma aplicação ASP.NET Core já compilada) ou seja MAIS AGILIDADE E MENOS CUSTO DE MEMORIA E ARMAZENAMENTO
FROM mcr.microsoft.com/dotnet/aspnet:8.0-alpine AS final

#metadados OCI: versão, commit e repositório de origem (o GHCR usa o "source" para ligar a imagem ao repositório)
ARG VERSION=dev
ARG REVISION=local
LABEL org.opencontainers.image.title="media-escolar-api" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.source="https://github.com/enzoblousa/boletim-escolar"

#define o /app como o workfolder no container
WORKDIR /app
#como se fosse a ponte, copia o resultado da build passada guardada em /app e guarda na /app deste estágio final
COPY --from=build /app .
#variável de ambiente, escuta todas as portas da api:8080 dentro do container
ENV ASPNETCORE_URLS=http://+:8080
#declara que a porta do contâiner é 8080
EXPOSE 8080
#SEGURANÇA: roda como o usuário sem privilégios "app" (já existe na imagem oficial), e não como root
USER $APP_UID
#o docker consulta /health periodicamente e marca o container como healthy/unhealthy (wget vem no busybox do alpine)
HEALTHCHECK --interval=10s --timeout=3s --start-period=15s --retries=3 \
    CMD wget -qO- http://localhost:8080/health || exit 1
#comando executado assim que o contâiner é iniciado.
ENTRYPOINT ["dotnet", "MediaEscolar.Api.dll"]



# Por que multi-stage?
# Sem o multi-stage, a imagem final teria o SDK inteiro (compilador, ferramentas de build) ocupando espaço e superfície de ataque sem necessidade em produção
# Só o estágio de build precisa disso. Com dois estágios, a imagem publicada (aspnet:8.0-alpine + DLLs) fica bem menor e mais segura, e o código-fonte/projetos de teste nem chegam a existir na imagem final.
