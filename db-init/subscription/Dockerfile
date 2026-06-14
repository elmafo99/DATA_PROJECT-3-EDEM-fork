FROM alpine:3.19
RUN apk add --no-cache postgresql-client
WORKDIR /app
COPY create_sub.sh .
RUN chmod +x create_sub.sh
CMD ["./create_sub.sh"]
