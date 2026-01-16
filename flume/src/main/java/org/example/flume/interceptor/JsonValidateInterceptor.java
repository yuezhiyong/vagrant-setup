package org.example.flume.interceptor;

import com.google.gson.Gson;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.reflect.TypeToken;
import org.apache.commons.collections.CollectionUtils;
import org.apache.flume.Context;
import org.apache.flume.Event;
import org.apache.flume.interceptor.Interceptor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

public class JsonValidateInterceptor implements Interceptor {

    private static final Logger LOGGER = LoggerFactory.getLogger(JsonValidateInterceptor.class);

    @Override
    public void initialize() {

    }

    @Override
    public Event intercept(Event event) {
        Map<String, String> headers = event.getHeaders();
        String log = new String(event.getBody(), StandardCharsets.UTF_8);
        Pair<Long, Boolean> headerPair = hasHeaderTs(log);
        if (headerPair.getSecond()) {
            LOGGER.info("start add timestamp:{}", headerPair.getFirst());
            Long ts = headerPair.getFirst();
            headers.put("timestamp", ts + "");
        }
        return event;
    }

    private static Pair<Long, Boolean> hasHeaderTs(String body) {
        try {
            Map<String, Object> resMap = new Gson().fromJson(body, new TypeToken<Map<String, Object>>() {
            }.getType());
            Object tsObj = resMap.get("ts");
            if (tsObj != null) {
                String ts = tsObj.toString();
                Long tsValue = (long) Double.parseDouble(ts);
                return new Pair<>(tsValue, true);
            }
        } catch (Exception e) {
            LOGGER.error("无法正确处理当前Event:{}", body);
        }
        return new Pair<>(null, false);
    }

    public static void main(String[] args) {
        String json = "{\"common\":{\"ar\":\"29\",\"ba\":\"xiaomi\",\"ch\":\"web\",\"is_new\":\"0\",\"md\":\"xiaomi 13\",\"mid\":\"mid_446\",\"os\":\"Android 13.0\",\"sid\":\"29229754-a940-45b2-af60-1a0f103456a7\",\"uid\":\"144\",\"vc\":\"v2.1.134\"},\"page\":{\"during_time\":17464,\"item\":\"559\",\"item_type\":\"order_id\",\"last_page_id\":\"order\",\"page_id\":\"payment\"},\"ts\":1704727866717}";
        Object res = hasHeaderTs(json);
        System.out.println(res);
    }

    @Override
    public List<Event> intercept(List<Event> list) {
        if (CollectionUtils.isEmpty(list)) {
            return new ArrayList<>();
        }
        List<Event> pass = new ArrayList<>();
        for (Event event : list) {
            String body = new String(event.getBody());
            Pair<Long, Boolean> has = hasHeaderTs(body);
            if (!has.getSecond()) {
                LOGGER.warn("当前事件不准确:{}", body);
                continue;
            }
            event.getHeaders().put("timestamp", has.getFirst() + "");
            pass.add(event);
        }
        return pass;
    }

    @Override
    public void close() {

    }


    /**
     * 关键在这里 ↓↓↓
     */
    public static class Builder implements Interceptor.Builder {

        @Override
        public Interceptor build() {
            return new JsonValidateInterceptor();
        }

        @Override
        public void configure(Context context) {
            // 读取 flume.conf 参数
        }
    }

}
