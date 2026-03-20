FROM node:22-bookworm-slim

ARG MCP_EVERYTHING_VERSION=latest
ENV PORT=3001

RUN npm install -g "@modelcontextprotocol/server-everything@${MCP_EVERYTHING_VERSION}" \
  && npm cache clean --force

EXPOSE 3001

USER 1000:1000

CMD ["sh", "-c", "npm run -g start:streamableHttp --prefix \"$(npm root -g)/@modelcontextprotocol/server-everything\""]
