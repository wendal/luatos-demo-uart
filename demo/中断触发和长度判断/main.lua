
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "uartdemo"
VERSION = "1.0.1"
-- sys库是标配
_G.sys = require("sys")

--[[
关于硬件接线:
1. 对大部分芯片/模组而已, 引脚引出的都是 TTL电平, 一般是 1.8V 或者 3.3V
2. TTL电平是不能直接接 RS232 或 RS485 的, 强行接上有烧毁的风险, 且数据肯定不对
3. 开发板上若带有RS232或者RS485转换芯片, 才能接对应的外部设备
4. 若使用RS232/RS485转换小板子(淘宝有),注意供电和接线说明
5. 注意 UART的接线规律, A设备的TX 要接 B 设备的RX, 同理 A设备的RX 要接 B设备的TX
6. 除TX/RX外, GND也要接上
]]

-- 按设备实际情况, 声明所需要的uart编号, 通常是 0 1 2 3等数值
-- 若设备支持USB虚拟串口, 那么也可以是 VUART_0
-- local uart_id = 0
-- local uart_id = 1
local uart_id = 2

-- 按实际情况设置uart的参数, 可以参考API文档
-- https://wiki.luatos.com/api/uart.html
-- 若使用RS485, 则留意文档中关于 "485模式" 的描述,自动控制485的方向
uart.setup(uart_id, 9600)
-- uart.setup(uart_id, 921600)

-------------------------------------------------
-- 以下是中断模式/回调模式下读取数据的演示

-- 这里定义了一个buff, 用途是为了在回调/Task中传递数据
local rxbuff = "" 
-- 定义一个topic, 方便传递消息
local uart_tx_topic = "uart_tx"
-- 回调函数的作用是, 当uart有可读取的数据, 这个函数就会被触发
uart.on(uart_id, "receive", function(id, len)
    log.info("uart", "evt", id, len)

    -- 这里为啥是循环呢? 因为单次uart.read不一定能全部读取完成
    -- 这跟底层适配有关系, 虽然大部分场景是可以一次读完的
    while 1 do
        -- 读取数据, 这里的512代表字节, 其实作用不大
        local data = uart.read(uart_id, 512)
        -- 底层总会返回一个字符串,但如果没有数据就会返回空字符串
        -- #就是取string或者数组的长度
        -- 通过判断长度, 判断是不是已经读取完毕
        if #data == 0 then
            -- 既然读取完成了, 这里的rxbuff应该不是空字符串
            -- 但处于健壮性的考虑, 这里多判断一下
            if #rxbuff > 0 then
                -- 对外通知已经读取完毕,第二个参数uart_id是备用的,是为了告知订阅者是哪个uart读取到数据了
                sys.publish(uart_tx_topic, uart_id)
            end
            -- 读取完成, 就退出循环了,同时也结束回调了
            break
        end
        -- 这段if属于防御, 避免rxbuff无限制的增长, 建议按需修改长度
        -- 如果确信一定能处理rxbuff, 那注释掉就可以了
        if #rxbuff > 2048 then
            log.warn("uart", "rxbuff is very large, cut it", #rxbuff)
            rxbuff = rxbuff:sub(#rxbuff - 2048)
        end
        
        -- 将数据拼接到rxbuff去, 等待数据读完
        rxbuff = rxbuff .. data

        -- 对应ESP32系列的, 还需要以下语句, 否则可能会持续200ms才退出循环
        -- if #data == len then
        --     break
        -- end
    end
end)

-- 以下是演示如何收取和处理数据

-- 方式1, task形式, 适合需要执行逻辑, 有额外调用sys.wait/sys.waitUntil的场景
sys.taskInit(function()
    while 1 do
        local ret = sys.waitUntil(uart_tx_topic, 1000)
        if not ret then
            if #rxbuff > 16 then
                -- 业务逻辑 xyz, 自行填充
                log.info("uart", "rx", rxbuff:toHex())
                -- 处理完成后, 对rxbuff进行清空或者裁剪
                rxbuff = ""
            end
        end
        log.info("uart", "等待数据")
    end
end)
-- 方式2, 订阅的方式, 适合函数式处理
sys.subscribe(uart_tx_topic, function(id)
    if #rxbuff > 16 then
        -- 业务逻辑 xyz, 自行填充
        log.info("uart", "rx", rxbuff:toHex())
        -- 处理完成后, 对rxbuff进行清空或者裁剪
        rxbuff = "" -- 直接清空
        -- rxbuff = rxbuff:sub(32) -- 根据已处理的长度进行裁剪
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
