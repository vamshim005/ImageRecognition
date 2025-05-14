package com.example;

import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.sqs.SqsAsyncClient;

import java.io.IOException;
import java.net.URI;
import java.util.UUID;

@RestController
@RequestMapping("/images")
@RequiredArgsConstructor
public class ImageController {

  private final S3Client s3;
  private final SqsAsyncClient sqs;
  @Value("${app.bucket}") String bucket;
  @Value("${app.queueUrl}") URI queue;

  @PostMapping(consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
  public ResponseEntity<UploadResponse> upload(@RequestPart MultipartFile file)
                           throws IOException {
    var key = UUID.randomUUID() + "-" + file.getOriginalFilename();
    s3.putObject(b -> b.bucket(bucket).key(key),
                 RequestBody.fromBytes(file.getBytes()));
    sqs.sendMessage(b -> b.queueUrl(queue.toString())
                          .messageBody(key));
    return ResponseEntity.accepted()
          .body(new UploadResponse(key));
  }
}

class UploadResponse {
  public String key;
  public UploadResponse(String key) { this.key = key; }
} 