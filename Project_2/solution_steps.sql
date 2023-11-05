--step_1
with first_payment as 
        (select user_id  
            , date_trunc('day', min(transaction_datetime)) as first_payment_date
        from skyeng_db.payments
        where status_name = 'success'
        group by user_id
        order by user_id),
--step_2
     all_dates as
        (select distinct date_trunc('day', class_start_datetime) as dt
        from skyeng_db.classes
        where class_start_datetime <'2017-01-01'),
--step_3
     all_dates_by_user as 
        (select user_id
            , dt
        from all_dates a
        join first_payment b
            on a.dt >= b.first_payment_date
            order by user_id, dt),
--step_4
    payments_by_dates as 
    (select user_id
        , date_trunc('day', transaction_datetime) as payment_date
        , sum(classes) as transaction_balance_change
    from skyeng_db.payments
    where status_name = 'success'
    group by user_id, date_trunc('day', transaction_datetime)
    order by date_trunc('day', transaction_datetime)),
--step_5
    payments_by_dates_cumsum as 
    (select c.user_id
        , c.dt
        , transaction_balance_change
        , sum(coalesce(transaction_balance_change,0)) over (partition by c.user_id order by c.dt) as transaction_balance_change_cs
     from all_dates_by_user c
     left join payments_by_dates d
        on c.user_id = d.user_id and c.dt = d.payment_date),
--step_6
    classes_by_dates as 
        (select user_id
            ,date_trunc('day', class_start_datetime) as start_date
            ,count(id_class)*(-1) as classes
        from skyeng_db.classes
        where (class_status = 'success' or class_status ='failed_by_student')
            and class_type <> 'trial'
        group by 1, 2),
--step_7
    classes_by_dates_dates_cumsum as 
        (select e.user_id
            , e.dt
            , classes 
            , sum (coalesce(classes,0)) over (partition by e.user_id order by dt) as classes_cs
        from all_dates_by_user e
        left join classes_by_dates f
            on e.user_id=f.user_id and e.dt=f.start_date),
--step_8
    balances as 
        (select q.user_id
            , q.dt
            , transaction_balance_change
            , transaction_balance_change_cs
            , classes
            , classes_cs
            , classes_cs + transaction_balance_change_cs as balance
        from payments_by_dates_cumsum q
        left join classes_by_dates_dates_cumsum p
            on q.dt=p.dt and q.user_id=p.user_id)

--Задание_1 
-- select *
-- from balances
-- order by user_id, dt 
-- limit 1000
-- Посмотрев на результаты, мы заметили, что баланс уроков принимает отрицательные значения. Возникает вопрос: 
-- почему камулятивная сумма проведенных уроков превышает камулятивную сумму оплаченных уроков? Триальные уроки мы не учитывали
-- Мы считали уроки из таблицы Payments с успешным статусом проведенной операции. Возможно здесь стоит уточнить, 
-- всегда ли успешно проведенная операция дает нам какое-то количество уроков?  



--step_9
select dt
   , sum(transaction_balance_change) as sum_balance_change
   , sum(transaction_balance_change_cs) as sum_balance_change_cs
   , sum(classes) as sum_classes
   , sum(classes_cs) as sum_classes_cs
   , sum(balance) as balance
from balances
group by dt
order by dt

--Итоговый график 
--На данном графике мы можем заметить как пикообразно распределнo количество оплаченных уроков и количество проведенных уроков по дням.
--Для проведенных занятий со середины года период таких пиков примерно неделя. Занятий в это время проводится больше. Вероятно, летом- подготовка к учебному году, осень - учеба. 
-- Но Резкого роста не наблюдаем, процесс соответствует классическому поведению еженедельного проведения занятий. 
-- Скачки - дни, в которые проходит основная масса уроков.
-- Пики оплаченных занятий ведут себя более произвольно, резкими скачками. Полагаем, что на это может влиять возможность покупать занятия пакетами.Активность пиков происходит в момент начала учебного года.
-- Накопительная сумма по обоим параметрам - равномерно растущая. И при этом баланс к концу года растет. 
--По графику мы понимаем, что это происходит не по причине того, что значительно меньше стали уроков проводить. По дням есть перевес то одного, то другого параметра
-- но по суммам мы имеем положительный баланс.
--такие графики хорошо строить для того, чтобы выявит выраженные изменения - положительные для бизнес процесса или нет и понять их причину.
--Например, почему 1 ноября было куплено больше всего уроков. Что этому поспособствовало.

--  Гипотезы по урокам
-- - В зимние праздники ученики предпочитают больше отдыхать, чем заниматься
-- - Перед началом учебного года и в процессе процесс с урока становится стабильным и регулярным
-- - Ученики в осенний период активнее покупают уроки и занимаются
-- - В майские праздники ученики отдыхают и немного занимаются, а покупать новые уроки предпочитают после 