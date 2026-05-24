FROM alpine:3.19
RUN apk add --no-cache postgresql-client
WORKDIR /app
COPY schema.sql .
COPY init.sh .
RUN chmod +x init.sh
CMD ["./init.sh"]
