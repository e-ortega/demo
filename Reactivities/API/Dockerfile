# Stage 1: build
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src

# copy csproj(s) and restore first to leverage caching
COPY Reactivities/API/*.csproj ./Reactivities/API/
# if solution file is needed (faster restore across projects)
COPY Reactivities/*.sln ./Reactivities/
COPY Reactivities/Domain/ ./Reactivities/Domain/
COPY Reactivities/Application/ ./Reactivities/Application/
COPY Reactivities/Persistance/ ./Reactivities/Persistance/
# copy API code after restore step
COPY Reactivities/API/ ./Reactivities/API/

WORKDIR /src/Reactivities/API
RUN dotnet restore API.csproj

# Build and publish
ARG CONFIGURATION=Release
RUN dotnet publish API.csproj -c $CONFIGURATION -o /app/publish /p:PublishTrimmed=false

# Stage 2: runtime
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish .
# Listen on port 80 in container
ENV ASPNETCORE_URLS=http://+:80
EXPOSE 80
ENTRYPOINT ["dotnet", "API.dll"]
