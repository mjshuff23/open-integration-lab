import { NestFactory } from "@nestjs/core";
import { AppModule } from "./app.module";

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.setGlobalPrefix("api");
  app.enableCors({ origin: process.env.FRONTEND_URL, credentials: true });
  app.enableShutdownHooks();
  const port = process.env.PORT ?? 4000;
  await app.listen(port);
}
bootstrap();
