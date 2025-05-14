package com.example;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Bean;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.rekognition.RekognitionClient;
import software.amazon.awssdk.services.rekognition.model.Image;
import software.amazon.awssdk.services.s3.S3Client;
import java.io.InputStream;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.Message;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.beans.factory.annotation.Autowired;

@SpringBootApplication
public class WorkerApp {
  public static void main(String[] args) {
    SpringApplication.run(WorkerApp.class, args);
  }
}

@Component
class SqsImageHandler {
  private final S3Client s3;
  private final RekognitionClient rekognition;
  private final SqsClient sqs;
  @Value("${app.bucket}") String bucket;
  @Value("${sqs.queue.url}") String queueUrl;

  @Autowired
  public SqsImageHandler(S3Client s3, RekognitionClient rekognition, SqsClient sqs) {
    this.s3 = s3;
    this.rekognition = rekognition;
    this.sqs = sqs;
  }

  // Poll SQS every 5 seconds
  @Scheduled(fixedDelay = 5000)
  public void pollSqs() {
    java.util.List<Message> messages = sqs.receiveMessage(r -> r.queueUrl(queueUrl).maxNumberOfMessages(5)).messages();
    for (Message msg : messages) {
      try {
        handle(msg.body());
        sqs.deleteMessage(r -> r.queueUrl(queueUrl).receiptHandle(msg.receiptHandle()));
      } catch (Exception e) {
        // Log and continue
        e.printStackTrace();
      }
    }
  }

  void handle(String key) {
      InputStream img = s3.getObject(b -> b.bucket(bucket).key(key));
      var labels = rekognition.detectLabels(r -> r.image(
                         Image.builder().bytes(SdkBytes.fromInputStream(img)).build()));
      var resultKey = key.replaceFirst("\\.", "_labels.json");
      s3.putObject(b -> b.bucket(bucket).key(resultKey),
                   RequestBody.fromString(labels.toString()));
  }
}