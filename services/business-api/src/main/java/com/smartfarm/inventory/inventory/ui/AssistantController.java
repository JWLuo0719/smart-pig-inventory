package com.smartfarm.inventory.inventory.ui;

import com.smartfarm.inventory.inventory.application.AssistantInsightService;
import com.smartfarm.inventory.inventory.application.AssistantInsightService.AssistantBrief;
import java.time.LocalDate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** 智能体洞察：把当日数据翻译成带证据的行动建议（只读）。 */
@RestController
@RequestMapping("/api/v1/assistant")
public class AssistantController {

    private final AssistantInsightService service;

    public AssistantController(AssistantInsightService service) {
        this.service = service;
    }

    @GetMapping("/insights")
    AssistantBrief insights(@RequestParam(required = false) LocalDate businessDate) {
        return service.insights(businessDate == null ? LocalDate.now() : businessDate);
    }
}
