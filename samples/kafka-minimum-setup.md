# Kafka Minimum Setup (Producer Side)

Simple steps to send data from a Spring Boot service to Kafka. This is the minimum only. We will refine it later.

> Checked against the Apache Kafka 4.4 quickstart and the Spring Boot 4 and Spring for Apache Kafka 4.x documentation. Spring Boot 3 differences are marked.

## The big picture

Kafka is a middleman (also called a broker). Your service is the **producer**. It puts a message into a named mailbox called a **topic**. Once Kafka has stored the message, your job is done. Another service, the **consumer**, reads it later.

## First: which Spring Boot version do you have?

Open `pom.xml` and look at the version in the `<parent>` block. It changes two things below.

| | Spring Boot 4.x | Spring Boot 3.x |
|---|---|---|
| Dependency (Step 2) | `spring-boot-starter-kafka` | `spring-kafka` |
| JSON serializer (Step 3) | `JacksonJsonSerializer` | `JsonSerializer` |

Why this matters: in Spring Boot 4, plain `spring-kafka` does not switch on the auto-configuration. You must use the starter. Also, `JsonSerializer` is the older Jackson 2 version and was replaced by `JacksonJsonSerializer` in Spring Kafka 4.

## Step 1: Start Kafka

**Why:** Kafka is a separate server. If it is not running, there is nowhere to send your data.

**Example (Docker):**

```bash
docker run -d --name kafka -p 9092:9092 apache/kafka:4.4.0
```

Now Kafka is running at `localhost:9092`. To stop and remove it later: `docker rm -f kafka`.

## Step 2: Add the dependency

**Why:** This gives your project the tools to talk to Kafka.

**Example (pom.xml), Spring Boot 4.x:**

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-kafka</artifactId>
</dependency>
```

**Example (pom.xml), Spring Boot 3.x:**

```xml
<dependency>
    <groupId>org.springframework.kafka</groupId>
    <artifactId>spring-kafka</artifactId>
</dependency>
```

Do not write a version number. Spring Boot picks the correct one for you.

## Step 3: Add producer config in application.properties

**Why:** Your service needs to know where Kafka is and how to convert your object into bytes.

**Example, Spring Boot 4.x:**

```properties
spring.kafka.bootstrap-servers=localhost:9092
spring.kafka.producer.key-serializer=org.apache.kafka.common.serialization.StringSerializer
spring.kafka.producer.value-serializer=org.springframework.kafka.support.serializer.JacksonJsonSerializer
spring.kafka.producer.acks=all
```

**Example, Spring Boot 3.x:** same file, but change only the value serializer line:

```properties
spring.kafka.producer.value-serializer=org.springframework.kafka.support.serializer.JsonSerializer
```

What each line means:

- `bootstrap-servers` is the address of Kafka (host and port).
- `key-serializer` turns the message key into bytes. Here the key is a plain string.
- `value-serializer` turns your Java object into JSON bytes. Kafka cannot read your Java class, so we send JSON.
- `acks=all` means Kafka confirms only after the message is safely stored. Since Kafka 3.0 this is already the default, so writing it just makes it visible.

## Step 4: Create the topic

**Why:** The topic is the named mailbox. The producer and the consumer must use the same name.

**Example:**

```java
package com.example.comments;

import org.apache.kafka.clients.admin.NewTopic;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.config.TopicBuilder;

@Configuration
public class KafkaTopicConfig {

    @Bean
    public NewTopic commentsTopic() {
        return TopicBuilder.name("comments-topic")
                .partitions(1)
                .replicas(1)
                .build();
    }
}
```

Spring creates `comments-topic` on the broker when the app starts. It is not needed if the topic already exists.

## Step 5: Send the message

**Why:** This is the line that hands your data to Kafka.

First, the data class. This is what turns into JSON:

```java
package com.example.comments;

public class CommentEvent {

    private String comment;
    private Long userId;

    public CommentEvent() {
    }

    public CommentEvent(String comment, Long userId) {
        this.comment = comment;
        this.userId = userId;
    }

    public String getComment() { return comment; }
    public void setComment(String comment) { this.comment = comment; }

    public Long getUserId() { return userId; }
    public void setUserId(Long userId) { this.userId = userId; }
}
```

Then the sender:

```java
package com.example.comments;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Service;

@Service
public class CommentProducer {

    private static final Logger log = LoggerFactory.getLogger(CommentProducer.class);
    private static final String TOPIC = "comments-topic";

    private final KafkaTemplate<String, CommentEvent> kafkaTemplate;

    public CommentProducer(KafkaTemplate<String, CommentEvent> kafkaTemplate) {
        this.kafkaTemplate = kafkaTemplate;
    }

    public void send(CommentEvent event) {
        String key = String.valueOf(event.getUserId());

        kafkaTemplate.send(TOPIC, key, event).whenComplete((result, ex) -> {
            if (ex != null) {
                log.error("Kafka send failed for userId {}", key, ex);
            } else {
                log.info("Saved in Kafka. partition={}, offset={}",
                        result.getRecordMetadata().partition(),
                        result.getRecordMetadata().offset());
            }
        });
    }
}
```

The three values in `send` are the topic name, the key, and the message. `send` does not wait. It returns straight away, and `whenComplete` runs later to tell you if Kafka really stored it.

Now call it from your comment code (for example, your controller):

```java
commentProducer.send(new CommentEvent("Nice post", 1L));
```

The JSON that goes into Kafka looks like this:

```json
{"comment":"Nice post","userId":1}
```

## Step 6: Check that it worked

**Why:** To confirm the message really reached Kafka before you build the consumer.

**Example:**

```bash
docker exec -it kafka /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic comments-topic --from-beginning
```

If you see your JSON printed, the producer side works. Press `Ctrl+C` to stop.

## Step 7: Consumer config (later)

**Why:** The receiving service needs the same address, a group id, and a deserializer to turn JSON back into an object. We will do this next.

**Preview, Spring Boot 4.x:**

```properties
spring.kafka.bootstrap-servers=localhost:9092
spring.kafka.consumer.group-id=comments-group
spring.kafka.consumer.auto-offset-reset=earliest
spring.kafka.consumer.key-deserializer=org.apache.kafka.common.serialization.StringDeserializer
spring.kafka.consumer.value-deserializer=org.springframework.kafka.support.serializer.JacksonJsonDeserializer
spring.kafka.consumer.properties[spring.json.value.default.type]=com.example.comments.CommentEvent
spring.kafka.consumer.properties[spring.json.trusted.packages]=com.example.comments
```

For Spring Boot 3.x, use `JsonDeserializer` instead of `JacksonJsonDeserializer`.

Two lines are special:

- `spring.json.trusted.packages` tells Spring which packages it is allowed to turn JSON into. Without it, the consumer refuses.
- `spring.json.value.default.type` is the class to build when the message does not say which class it is.

## Common problems

- **Connection refused or timeout:** Kafka is not running, or the port is wrong. Run `docker ps` and check that `kafka` is up and mapped to 9092.
- **No `KafkaTemplate` bean found (Spring Boot 4):** you added `spring-kafka` instead of `spring-boot-starter-kafka`.
- **Nothing printed in Step 6:** the send may have failed. Check your app log for the "Kafka send failed" line.
