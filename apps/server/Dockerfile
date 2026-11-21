# syntax=docker/dockerfile:1.7
FROM eclipse-temurin:21-jdk-alpine AS build
RUN apk add --no-cache bash
WORKDIR /workspace
COPY . .
RUN chmod +x gradlew && ./gradlew --no-daemon bootJar

FROM eclipse-temurin:21-jre-alpine
RUN addgroup -S mirrorline && adduser -S mirrorline -G mirrorline
WORKDIR /app
COPY --from=build /workspace/build/libs/mirrorline-server-*.jar app.jar
USER mirrorline
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
