package com.example;

import io.awspring.cloud.sqs.annotation.SqsListener;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.aws.messaging.listener.annotation.EnableSqs;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.rekognition.RekognitionClient;
import software.amazon.awssdk.services.rekognition.model.Image;
import software.amazon.awssdk.services.s3.S3Client;
import java.io.InputStream;

@EnableSqs
@SpringBootApplication
public class WorkerApp {
  public static void main(String[] args) { SpringApplication.run(WorkerApp.class, args); }
}

@Component
class SqsImageHandler {
  private final S3Client s3;
  private final RekognitionClient rekognition;
  @Value("${app.bucket}") String bucket;

  public SqsImageHandler(S3Client s3, RekognitionClient rekognition) {
    this.s3 = s3;
    this.rekognition = rekognition;
  }

  @SqsListener("${app.queueName}")
  void handle(String key) {
      InputStream img = s3.getObject(b -> b.bucket(bucket).key(key));
      var labels = rekognition.detectLabels(r -> r.image(
                         Image.builder().bytes(SdkBytes.fromInputStream(img)).build()));
      var resultKey = key.replaceFirst("\\.", "_labels.json");
      s3.putObject(b -> b.bucket(bucket).key(resultKey),
                   RequestBody.fromString(labels.toString()));
  }
} 