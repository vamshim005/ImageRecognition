package com.example;

import io.awspring.cloud.messaging.config.annotation.EnableSqs;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
@EnableSqs               // boot-strap SQS listener threads
public class WorkerApp {

    public static void main(String[] args) {
        SpringApplication.run(WorkerApp.class, args);
    }
}