import { PrismaClient } from "@prisma-app/client";

const prisma = new PrismaClient();
prisma.$connect();

export { prisma };
