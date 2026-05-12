# 🔨 BUILD STAGE
FROM eclipse-temurin:17-jdk-jammy AS builder

WORKDIR /build
COPY app/target/*.jar app.jar

# Extract layers for optimization
RUN mkdir -p /build/target/dependency && \
    cd /build/target/dependency && \
    jar -xf /build/app.jar

# 🚀 RUNTIME STAGE - Use JRE only (much smaller)
FROM eclipse-temurin:17-jre-jammy

WORKDIR /app

# Copy pre-built dependencies from builder
COPY --from=builder /build/target/dependency/BOOT-INF/lib ./lib
COPY --from=builder /build/target/dependency/BOOT-INF/classes ./classes
COPY --from=builder /build/target/dependency/META-INF ./META-INF

# Create non-root user
RUN useradd -m -u 10001 -s /sbin/nologin appuser && chown -R appuser:appuser /app

USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:8080/actuator/health || exit 1

# Use layered JAR for faster startup
ENTRYPOINT ["java", "-cp", ".:./lib/*:./classes", "org.springframework.boot.loader.JarLauncher"]