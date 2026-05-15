# syntax=docker/dockerfile:1
FROM eclipse-temurin:17-jdk-jammy as base
WORKDIR /build
COPY --chmod=0755 mvnw mvnw
COPY .mvn/ .mvn/

# Giai đoạn chạy Test: Build sẽ dừng nếu Test thất bại
FROM base as test
WORKDIR /build
COPY ./src src/
RUN --mount=type=bind,source=pom.xml,target=pom.xml \
    --mount=type=cache,target=/root/.m2 \
    ./mvnw test

# Giai đoạn tải thư viện (Dependencies)
FROM base as deps
WORKDIR /build
RUN --mount=type=bind,source=pom.xml,target=pom.xml \
    --mount=type=cache,target=/root/.m2 \
    ./mvnw dependency:go-offline -DskipTests

# Giai đoạn đóng gói file JAR
FROM deps as package
WORKDIR /build
COPY ./src src/
RUN --mount=type=bind,source=pom.xml,target=pom.xml \
    --mount=type=cache,target=/root/.m2 \
    ./mvnw package -DskipTests && \
    mv target/*.jar target/app.jar

# Giai đoạn giải nén để tối ưu hóa Layer
FROM package as extract
WORKDIR /build
RUN java -Djarmode=layertools -jar target/app.jar extract --destination target/extracted

# Giai đoạn DEVELOPMENT (Dành cho bạn lập trình và Debug)
FROM extract as development
WORKDIR /build
COPY --from=extract /build/target/extracted/dependencies/. ./
COPY --from=extract /build/target/extracted/spring-boot-loader/. ./
COPY --from=extract /build/target/extracted/snapshot-dependencies/. ./
COPY --from=extract /build/target/extracted/application/. ./
# Cấu hình mở cổng Debug 8000 và kết nối từ bên ngoài (*)
ENV JAVA_TOOL_OPTIONS="-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:8000"
CMD [ "java", "-Dspring.profiles.active=mysql", "org.springframework.boot.loader.launch.JarLauncher" ]

# Giai đoạn FINAL (Dành cho chạy thực tế)
FROM eclipse-temurin:17-jre-jammy AS final
WORKDIR /app
COPY --from=extract /build/target/extracted/dependencies/ ./
COPY --from=extract /build/target/extracted/spring-boot-loader/ ./
COPY --from=extract /build/target/extracted/snapshot-dependencies/ ./
COPY --from=extract /build/target/extracted/application/ ./
EXPOSE 8080
ENTRYPOINT [ "java", "-Dspring.profiles.active=mysql", "org.springframework.boot.loader.launch.JarLauncher" ]