package com.example;

import io.awspring.cloud.messaging.listener.annotation.SqsListener;
import org.springframework.stereotype.Component;

@Component
public class SqsImageHandler {

    @SqsListener("${sqs.queue.url}")
    public void handle(String s3EventJson) {
        System.out.println("Received:\n" + s3EventJson);
    }
}