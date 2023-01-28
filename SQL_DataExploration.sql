USE ARENA 
GO


---) דוח המציג את כמות השחקנים אשר נושאים כל סוג כרטיס, לפי כל מגדר וקבוצת גיל 

SELECT *
FROM (SELECT p.player_id, gender, age_group, credit_card_type
	FROM players AS P JOIN paying_method AS PM
	ON P.player_id=PM.player_id) AS TBL
PIVOT (COUNT(player_id) FOR credit_card_type IN([americanexpress],[mastercard],[visa])) AS PVT
ORDER BY gender 


---------------)Game Sessions Analysis

---) הצגת כמות הסשנים עבור כל משחק, ודירוג את המשחקים לפי כמות הסשנים, מהגבוה לנמוך

SELECT G.game_name,
			COUNT(*) AS 'NUM_SESSIONS',
				DENSE_RANK() OVER(ORDER BY COUNT(*) DESC) AS 'NUM_SESSIONS_RANK'
FROM game_sessions AS GS JOIN games AS G
	ON G.id=GS.game_id
GROUP BY G.game_name

---) דירוג את המשחקים לפי כמות הזמן (דקות) בה שיחקו בכל אחד מהם
SELECT g.game_name, 
       SUM(DATEDIFF(MINUTE, gs.session_begin_date, gs.session_end_date)) AS 'total_playing_minutes',
	   DENSE_RANK() OVER (ORDER BY SUM(DATEDIFF(MINUTE, gs.session_begin_date, gs.session_end_date)) DESC) AS 'total_playing_minutes_rank'
FROM game_sessions gs JOIN games g 
ON   gs.game_id = g.id 
GROUP BY g.game_name

---) המשחק בו שיחקו הכי הרבה זמן, בכל קבוצת גיל
;WITH play_cte AS 
	(
	SELECT p.age_group, g.game_name, 
		   SUM(DATEDIFF(MINUTE, gs.session_begin_date, gs.session_end_date)) AS 'total_playing_minutes',
		   DENSE_RANK() OVER (PARTITION BY p.age_group
							  ORDER BY SUM(DATEDIFF(MINUTE, gs.session_begin_date, gs.session_end_date)) DESC) 
							  AS 'total_playing_minutes_rank'
	FROM game_sessions gs JOIN games g 
	ON   gs.game_id = g.id 
						  JOIN players p
	ON   p.player_id = gs.player_id 
	GROUP BY g.game_name, p.age_group
	)
SELECT age_group, game_name, total_playing_minutes
FROM play_cte 
WHERE total_playing_minutes_rank = 1 

------------)Revenue Analysis

---) הצגת את האיזון לאורך כל סשן (balance)

SELECT session_id, action_id, action_type,
       CASE WHEN action_type = 'loss' THEN amount * -1 ELSE amount END AS 'amount',
       SUM(CASE WHEN action_type = 'loss' THEN amount * -1 ELSE amount END)
	   OVER (PARTITION BY session_id ORDER BY action_id) AS 'balance'
FROM session_details 

---) כמה סשנים הסתיימו ברווח, וכמה סשנים הסתיימו בהפסד
;WITH Q1 AS 
(
SELECT session_id, action_id, action_type,
       CASE WHEN action_type = 'loss' THEN amount * -1 ELSE amount END AS 'amount',
       SUM(CASE WHEN action_type = 'loss' THEN amount * -1 ELSE amount END)
	   OVER (PARTITION BY session_id ORDER BY action_id) AS 'balance',
	   DENSE_RANK() OVER(PARTITION BY session_id ORDER BY action_id DESC) AS 'RANKING'
FROM session_details 
)
SELECT COUNT(CASE WHEN balance < 0 THEN 1 END)  AS 'total_losses', 
       COUNT(CASE WHEN balance >= 0 THEN 1 END) AS 'total_gains'
FROM Q1
WHERE Q1.RANKING =1

---) כמה סשנים הסתיימו ברווח, כמה סשנים הסתיימו בהפסד ? בכל מגדר וקבוצת גיל

;WITH Q1 AS (
SELECT SD.session_id,SD.action_id,P.gender,P.age_group,
		CASE WHEN SD.action_type LIKE 'loss' THEN SD.amount*-1 
		ELSE SD.amount
		END AS 'amount',
		SUM(CASE WHEN SD.action_type LIKE 'loss' THEN SD.amount*-1 
		ELSE SD.amount
		END) OVER(PARTITION BY SD.session_id ORDER BY SD.action_id ) AS 'balance',
		DENSE_RANK() OVER(PARTITION BY SD.session_id ORDER BY SD.action_id DESC ) AS 'rank'
FROM game_sessions AS GM JOIN players AS P
	ON P.player_id=GM.player_id JOIN session_details AS SD
	ON SD.session_id=GM.session_id
) 
SELECT Q1.gender,Q1.age_group,
			SUM(CASE WHEN Q1.balance>=0 THEN 1 ELSE 0 END) AS 'TOTAL GAINS',
			SUM(CASE WHEN Q1.balance<0 THEN 1 ELSE 0 END) AS 'TOTAL LOSSES'
FROM Q1
WHERE Q1.rank =1
GROUP BY Q1.gender,Q1.age_group

---)  סכום הרווח \ הפסד הכולל לכל שחקן

SELECT  DISTINCT player_id ,
		SUM(CASE WHEN action_type = 'loss' THEN amount * -1 ELSE amount END)
		OVER (PARTITION BY player_id) AS 'balance'
from 		   [dbo].[session_details] AS S
JOIN  [dbo].[game_sessions]  G
ON S.session_id = G.session_id

------------)Revenue Trend Analysis

---) הצגת את הרווחים \ הפסדים של החברה לפי כל שנה ורבעון

;WITH balance_cte AS 
	(
	SELECT session_id, action_id,
		   SUM(CASE WHEN action_type = 'loss' THEN amount * -1 ELSE amount END)
		   OVER (PARTITION BY session_id ORDER BY action_id) AS 'balance'
	FROM session_details 
	), rn_actions AS 
	(SELECT session_id, action_id, balance, 
	        ROW_NUMBER() OVER (PARTITION BY session_id ORDER BY action_id DESC) AS 'rn_action'
	FROM balance_cte)
SELECT YEAR(gs.session_begin_date) AS 'year', DATEPART(QUARTER, gs.session_begin_date) AS 'quarter',
       SUM(CASE WHEN balance < 0 THEN balance END) * -1 AS 'house_gains', 
       SUM(CASE WHEN balance >= 0 THEN balance END)* -1 AS 'house_losses', 
	   (SUM(CASE WHEN balance < 0 THEN balance END) * -1) - SUM(CASE WHEN balance >= 0 THEN balance END) AS 'overall_gain_loss'
FROM rn_actions ra JOIN game_sessions gs 
ON   ra.session_id = gs.session_id 
WHERE rn_action = 1
GROUP BY YEAR(gs.session_begin_date), DATEPART(QUARTER, gs.session_begin_date)
ORDER BY YEAR(gs.session_begin_date), DATEPART(QUARTER, gs.session_begin_date)

---)  (הצגת את 3 החודשים הכי טובים והכי גרועים של החברה (לפי רווח והפסד
;WITH balance_cte AS 
	(
	SELECT session_id, action_id,
		   SUM(CASE WHEN action_type = 'loss' THEN amount * -1 ELSE amount END)
		   OVER (PARTITION BY session_id ORDER BY action_id) AS 'balance'
	FROM session_details 
	), rn_actions AS 
	(SELECT session_id, action_id, balance, 
	        ROW_NUMBER() OVER (PARTITION BY session_id ORDER BY action_id DESC) AS 'rn_action'
	FROM balance_cte), overall_balance AS 
	(
	SELECT YEAR(gs.session_begin_date) AS 'year', DATEPART(MONTH, gs.session_begin_date) AS 'month',
		   SUM(CASE WHEN balance < 0 THEN balance END) * -1 AS 'house_gains', 
		   SUM(CASE WHEN balance >= 0 THEN balance END)* -1 AS 'house_losses', 
		   (SUM(CASE WHEN balance < 0 THEN balance END) * -1) - SUM(CASE WHEN balance >= 0 THEN balance END) AS 'overall',
		   DENSE_RANK() OVER (ORDER BY (SUM(CASE WHEN balance < 0 THEN balance END) * -1) - SUM(CASE WHEN balance >= 0 THEN balance END) DESC) AS 'profit_rank',
		   DENSE_RANK() OVER (ORDER BY (SUM(CASE WHEN balance < 0 THEN balance END) * -1) - SUM(CASE WHEN balance >= 0 THEN balance END)) AS 'loss_rank'
	FROM rn_actions ra JOIN game_sessions gs 
	ON   ra.session_id = gs.session_id 
	WHERE rn_action = 1
	GROUP BY YEAR(gs.session_begin_date), DATEPART(MONTH, gs.session_begin_date)
	)
SELECT year, month, house_gains, house_losses, overall, 
       CASE WHEN overall < 0 THEN CONCAT('Loss Top-',loss_rank) ELSE CONCAT('Gain Top-',profit_rank) END AS 'overall_rank'
FROM overall_balance
WHERE profit_rank <= 3 OR loss_rank <= 3
ORDER BY CASE WHEN overall < 0 THEN 1 ELSE 0 END, ABS(overall) DESC
---------------------------------------------------------------------------------------------------------------------

SELECT *
FROM session_details

SELECT *
FROM games

SELECT *
FROM players

SELECT *
FROM paying_method

SELECT *
FROM game_sessions
