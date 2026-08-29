package com.smartfarm.inventory;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class BusinessApiApplication {
    public static void main(String[] args) {
        SpringApplication.run(BusinessApiApplication.class, args);
    }
}

