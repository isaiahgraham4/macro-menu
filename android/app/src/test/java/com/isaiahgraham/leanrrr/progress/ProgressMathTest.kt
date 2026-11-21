package com.isaiahgraham.leanrrr.progress

import com.isaiahgraham.leanrrr.data.AppData
import com.isaiahgraham.leanrrr.data.BodyMeasurement
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.Goals
import com.isaiahgraham.leanrrr.data.LogEntry
import com.isaiahgraham.leanrrr.data.Moment
import com.isaiahgraham.leanrrr.data.Portion
import com.isaiahgraham.leanrrr.data.WeightEntry
import com.isaiahgraham.leanrrr.data.WeightGoal
import com.isaiahgraham.leanrrr.data.achievements
import com.isaiahgraham.leanrrr.data.dayKey
import com.isaiahgraham.leanrrr.data.earning
import com.isaiahgraham.leanrrr.data.offerWeek
import com.isaiahgraham.leanrrr.data.stepsReachedMoment
import com.isaiahgraham.leanrrr.data.weighInMoment
import com.isaiahgraham.leanrrr.feature.progress.ActiveEnergy
import com.isaiahgraham.leanrrr.feature.progress.BodyMeasurements
import com.isaiahgraham.leanrrr.feature.progress.CheckIn
import com.isaiahgraham.leanrrr.feature.progress.Steps
import com.isaiahgraham.leanrrr.feature.progress.TrackingStreak
import com.isaiahgraham.leanrrr.feature.progress.WeeklyReview
import com.isaiahgraham.leanrrr.feature.progress.WeightTrend
import com.isaiahgraham.leanrrr.feature.progress.WeightTrend.GoalStatus.Direction
import com.isaiahgraham.leanrrr.feature.progress.WeightTrend.GoalStatus.Pace
import com.isaiahgraham.leanrrr.feature.progress.YearReview
import com.isaiahgraham.leanrrr.feature.progress.markingGoalReached
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import kotlin.math.abs

/** Expected results from ios/Tests/AppChecks.swift for the trend, goal, check-in, review and milestone maths. */
class ProgressMathTest {
    private val zone: ZoneId = ZoneId.systemDefault()
    private val day0: LocalDate = LocalDate.of(2026, 6, 1)
    private fun day(n: Int): Instant = day0.plusDays(n.toLong()).atTime(8, 0).atZone(zone).toInstant()
    private fun near(expected: Double, actual: Double, within: Double = 0.0001) = assertTrue("$actual is not $expected", abs(expected - actual) < within)

    @Test fun trendSmoothsAndFillsGaps() {
        val flat = WeightTrend.points((0 until 10).map { WeightEntry(date = day(it), kg = 80.0) })
        assertTrue(flat.size == 10 && flat.all { abs(it.trend - 80) < 0.0001 })
        near(80.4, WeightTrend.points(listOf(WeightEntry(date = day(0), kg = 80.0), WeightEntry(date = day(1), kg = 82.0)))[1].trend)
        near(80.69867, WeightTrend.points(listOf(WeightEntry(date = day(0), kg = 80.0), WeightEntry(date = day(3), kg = 82.0)))[1].trend)
        val drop = WeightTrend.points((0 until 14).map { WeightEntry(date = day(it), kg = 110.5) } + (14 until 21).map { WeightEntry(date = day(it), kg = 109.3) })
        near(110.26, drop[14].trend)
        assertTrue(abs(drop[20].trend - 109.3) < 0.3)
        assertEquals(8, WeightTrend.daysToCatchUp(110.4, 109.3))
        assertEquals(0, WeightTrend.daysToCatchUp(80.1, 80.0))
        assertTrue(WeightTrend.gapText(drop[14])!!.startsWith("Your trend is 1 kg above your last weigh-in"))
        assertNull(WeightTrend.gapText(flat[9]))
        val sameDay = WeightTrend.points(listOf(WeightEntry(date = day(0), kg = 80.0), WeightEntry(date = day(0).plusSeconds(3600), kg = 81.0)))
        assertTrue(sameDay.size == 1 && sameDay[0].kg == 81.0)
        assertTrue(WeightTrend.points(listOf(WeightEntry(date = day(0), kg = 5.0))).isEmpty())
        // The trend follows the scale less recent water.
        val wet = WeightEntry(date = day(0), kg = 81.0, waterKG = 0.9)
        val wetTrend = WeightTrend.points(listOf(WeightEntry(date = day(-1), kg = 80.0), wet))
        near(80 + 0.2 * (81 - 0.9 - 80), wetTrend[1].trend)
    }

    @Test fun weeklyChangeAndMaintenance() {
        val losing = WeightTrend.points((0 until 60).map { WeightEntry(date = day(it), kg = 90 - it * 0.1) })
        near(-0.7, WeightTrend.weeklyChange(losing, now = day(60))!!, 0.05)
        val steady = Food(id = "steady", name = "Steady", kj = 2000 * 4.184, cal = 2000.0, p = 100.0, c = 200.0, f = 70.0)
        val logs = (30 until 60).associate { dayKey(day(it)) to listOf(LogEntry(name = "Day", items = listOf(Portion(food = steady)), time = day(it))) }
        val maintenance = WeightTrend.maintenance(logs, losing, now = day(60))!!
        assertTrue(abs(maintenance.calories - 2770) < 60 && maintenance.loggedDays == 28)
        assertNull(WeightTrend.maintenance(emptyMap(), losing, now = day(60)))
    }

    private val today: LocalDate = LocalDate.now()
    private val todayStart: Instant = today.atStartOfDay(zone).toInstant()
    private fun weighIns(start: Double, perWeek: Double, weeks: Int) = (0..weeks * 7).map { d ->
        WeightEntry(date = today.plusDays((d - weeks * 7).toLong()).atStartOfDay(zone).toInstant(), kg = start + perWeek / 7 * d)
    }

    @Test fun goalStatusAndProjection() {
        val losing = WeightTrend.points(weighIns(90.0, -0.5, 4))
        val goal = WeightGoal(kg = 80.0, startKg = 90.0, set = todayStart)
        val status = WeightTrend.goalStatus(goal, losing, todayStart)!!
        assertTrue(status.direction == Direction.LOSE && status.pace == Pace.TOWARDS && status.projected != null)
        assertTrue(status.remaining > 7 && status.remaining < 9 && status.progress > 0.05 && status.progress < 0.3)
        assertTrue(ChronoUnit.DAYS.between(today, status.projected).toInt() / 7 in 14..30)
        val gaining = WeightTrend.points(weighIns(60.0, 0.4, 4))
        val gain = WeightTrend.goalStatus(WeightGoal(66.0, 60.0, todayStart), gaining, todayStart)!!
        assertTrue(gain.direction == Direction.GAIN && gain.pace == Pace.TOWARDS && gain.projected != null)
        val wrong = WeightTrend.goalStatus(WeightGoal(85.0, 90.0, todayStart), losing, todayStart)!!
        assertTrue(wrong.direction == Direction.LOSE && wrong.pace == Pace.TOWARDS)
        val away = WeightTrend.goalStatus(WeightGoal(95.0, 90.0, todayStart), losing, todayStart)!!
        assertTrue(away.direction == Direction.GAIN && away.pace == Pace.AWAY && away.projected == null)
        val flat = WeightTrend.points(weighIns(80.0, 0.0, 4))
        assertEquals(Pace.FLAT, WeightTrend.goalStatus(WeightGoal(75.0, 80.0, todayStart), flat, todayStart)!!.pace)
        val reached = WeightTrend.goalStatus(WeightGoal(79.95, 90.0, todayStart), flat, todayStart)!!
        assertTrue(reached.direction == Direction.REACHED && reached.progress == 1.0 && reached.projected == null)
        assertEquals(Pace.UNKNOWN, WeightTrend.goalStatus(goal, WeightTrend.points(weighIns(90.0, -0.5, 0)), todayStart)!!.pace)
        assertNull(WeightTrend.goalStatus(goal, emptyList(), todayStart))
        assertEquals(70L, ChronoUnit.DAYS.between(today, WeightTrend.date(5.0, 0.5, todayStart)))
        assertNull(WeightTrend.date(5.0, 0.0, todayStart))
        assertNull(WeightTrend.date(50.0, 0.1, todayStart))
        near(550.0, WeightTrend.dailyCalorieDifference(0.5), 0.01)
    }

    @Test fun goalReachedOnceAndWeighInMoments() {
        val before = AppData(weights = listOf(WeightEntry(date = todayStart.minusSeconds(86400), kg = 80.5)), weightGoal = WeightGoal(80.0, 90.0, todayStart))
        val after = before.copy(weights = (0 until 30).map { WeightEntry(date = todayStart.minusSeconds(it * 86400L), kg = 80.0) })
        val marked = after.markingGoalReached(before)
        assertNotNull(marked?.weightGoal?.reached)
        val again = marked!!.copy(weights = marked.weightLog + WeightEntry(date = todayStart, kg = 80.0))
        assertNull(again.markingGoalReached(marked))
        assertNull(after.markingGoalReached(after))
        val there = after.copy(weightGoal = WeightGoal(80.0, 80.0, todayStart))
        assertNull(there.markingGoalReached(before.copy(weightGoal = there.weightGoal)))
        val awayFromGoal = before.copy(weightGoal = before.weightGoal!!.copy(kg = 70.0)).weighInMoment as Moment.WeighIn
        assertTrue(awayFromGoal.moved == 9.5 && awayFromGoal.losing)
        assertFalse((before.copy(weightGoal = WeightGoal(90.0, 75.0, todayStart)).weighInMoment as Moment.WeighIn).losing)
        assertNull(before.copy(weightGoal = WeightGoal(75.0, 80.0, todayStart)).weighInMoment)
    }

    private val food = Food(name = "Test", kj = 0.0, cal = 500.0, p = 80.0, c = 60.0, f = 10.0)
    private fun logging(data: AppData, on: LocalDate): AppData {
        val key = dayKey(on)
        return data.copy(logs = data.logs + (key to ((data.logs[key] ?: emptyList()) + LogEntry(name = "T", items = listOf(Portion(food = food)), time = on.atStartOfDay(zone).toInstant()))))
    }

    @Test fun momentsAreEarnedOnce() {
        val (earned, firstMoments) = logging(AppData(), today).earning(AppData(), todayStart)
        assertEquals(listOf<Moment>(Moment.Meals(1)), firstMoments)
        val (second, hits) = logging(earned, today).earning(earned, todayStart)
        assertEquals(listOf("Protein"), (hits.first() as Moment.Targets).hits.map { it.name })
        val without = second.copy(logs = second.logs + (dayKey(today) to second.logs.getValue(dayKey(today)).dropLast(1)))
        assertTrue(logging(without, today).earning(without, todayStart).second.isEmpty())
        var streaking = AppData()
        for (back in 1 until 3) streaking = logging(streaking, today.minusDays(back.toLong()))
        val (third, thirdMoments) = logging(streaking, today).earning(streaking, todayStart)
        assertTrue(Moment.Streak(3) in thirdMoments)
        val (thirdAgain, againMoments) = logging(third, today).earning(third, todayStart)
        assertFalse(Moment.Streak(3) in againMoments)
        // The last target of the day gets the "every target" card instead.
        val full = Food(name = "Full", kj = 0.0, cal = 500.0, p = 160.0, c = 250.0, f = 70.0)
        val allGoals = AppData(goalSets = listOf(Goals(values = mapOf("cal" to 2200.0, "p" to 150.0, "c" to 250.0, "f" to 70.0))))
        val allHit = allGoals.copy(logs = mapOf(dayKey(today) to listOf(LogEntry(name = "F", items = listOf(Portion(food = full)), time = todayStart))))
        val allEarned = allHit.earning(allGoals, todayStart).second
        assertTrue(Moment.AllTargets(3) in allEarned && allEarned.none { it is Moment.Targets })
        // A missed day is marked as saved on the next log.
        var gapped = AppData()
        for (back in 2..5) gapped = logging(gapped, today.minusDays(back.toLong()))
        assertTrue(Moment.StreakSaved(5) in logging(gapped, today).earning(gapped, todayStart).second)
        // The shelf counts what was reached before it existed, and shows the next of each kind.
        val shelf = thirdAgain.achievements(today)
        assertTrue(shelf.any { it.moment == Moment.Streak(3) && it.earned } && shelf.any { it.moment == Moment.Streak(7) && !it.earned && it.left == "4 days to go" })
        assertTrue(shelf.any { it.moment == Moment.Meals(1) && it.earned } && shelf.any { it.moment == Moment.Meals(10) && !it.earned })
        assertFalse(shelf.any { it.moment == Moment.Streak(14) })
        // Steps count only when the goal is passed while the app is running.
        assertEquals(Moment.Steps(8100.0, 8000.0), stepsReachedMoment(mapOf("d" to 7000.0), mapOf("d" to 8100.0), 8000.0, "d"))
        assertNull(stepsReachedMoment(emptyMap(), mapOf("d" to 8100.0), 8000.0, "d"))
        assertNull(stepsReachedMoment(mapOf("d" to 8050.0), mapOf("d" to 8100.0), 8000.0, "d"))
        // Last week's card: once per week, and only with enough logged days.
        var week = AppData()
        for (back in 1..4) week = logging(week, today.minusDays(back.toLong()))
        val offered = week.offerWeek(today)!!
        assertEquals(4, (offered.second as Moment.Week).logged)
        assertNull(offered.first.offerWeek(today))
        assertNull(logging(logging(AppData(), today.minusDays(1)), today.minusDays(2)).offerWeek(today))
    }

    @Test fun yearReview() {
        val chicken = Food(chain = "kfc", name = "Chicken", kj = 0.0, cal = 400.0, p = 160.0)
        var data = AppData(logs = mapOf(
            "2026-03-01" to listOf(LogEntry(name = "Chicken", items = listOf(Portion(food = chicken))), LogEntry(name = "Chicken", items = listOf(Portion(food = chicken)))),
            "2026-03-02" to listOf(LogEntry(name = "Test", items = listOf(Portion(food = food))), LogEntry(name = "Quick add", items = listOf(Portion(food = food)))),
            "2025-03-02" to listOf(LogEntry(name = "Old", items = listOf(Portion(food = food)))),
        ), weightGoal = WeightGoal(80.0, 90.0, todayStart), weights = listOf(
            WeightEntry(date = LocalDate.of(2026, 2, 1).atStartOfDay(zone).toInstant(), kg = 90.0),
            WeightEntry(date = LocalDate.of(2026, 6, 1).atStartOfDay(zone).toInstant(), kg = 85.0)))
        val year = YearReview.make(data, 2026, setOf("kfc"))
        assertTrue(year.meals == 4 && year.days == 2 && year.topMeal == Pair("Chicken", 2) && year.topChain?.first == "kfc" && year.bestStreak == 2)
        assertTrue(year.proteinDays == 2 && year.weight?.losing == true && (year.weight?.moved ?: 0.0) > 0)
        data = data.copy(weightGoal = WeightGoal(95.0, 90.0, todayStart))
        assertNull(YearReview.make(data, 2026).weight)
        assertEquals(2026, YearReview.showing(LocalDate.of(2026, 12, 15)))
        assertEquals(2026, YearReview.showing(LocalDate.of(2027, 1, 15)))
        assertNull(YearReview.showing(LocalDate.of(2026, 11, 15)))
    }

    @Test fun weeklyReview() {
        val wrap = Food(id = "wrap", name = "Chicken wrap", kj = 2000.0, cal = 480.0, p = 35.0)
        val toast = Food(id = "toast", name = "Toast", kj = 1000.0, cal = 240.0, p = 8.0)
        val steady = Food(id = "steady", name = "Steady", kj = 8368.0, cal = 2000.0, p = 100.0)
        val logs = mutableMapOf<String, List<LogEntry>>()
        for (n in 0..1) logs[dayKey(day(n))] = listOf(LogEntry(name = "Wrap", items = listOf(Portion(food = wrap)), time = day(n)), LogEntry(name = "wrap", items = listOf(Portion(food = wrap)), time = day(n)))
        logs[dayKey(day(2))] = listOf(LogEntry(name = "Toast", items = listOf(Portion(food = toast)), time = day(2)))
        logs[dayKey(day(8))] = listOf(LogEntry(name = "Next week", items = listOf(Portion(food = steady)), time = day(8)))
        val week = AppData(logs = logs, weights = listOf(WeightEntry(date = day(-3), kg = 80.0), WeightEntry(date = day(5), kg = 79.0)))
        val review = WeeklyReview.make(week, Goals(), ending = day0.plusDays(6))
        assertTrue(review.loggedDays == 3 && review.averageCalories == 720.0 && abs(review.averageProtein!! - 148.0 / 3) < 0.001)
        assertTrue(review.calorieTarget == 2200.0 && review.proteinTarget == 150.0 && review.proteinDays == 0 && review.calorieDays == 3)
        near(-0.58389, review.weightChange!!)
        assertEquals(listOf(WeeklyReview.Meal("Wrap", 4)), review.topMeals)
        assertTrue(review.totalCalories == 2160.0 && review.totalCalorieTarget == 6600.0)
        assertEquals("Logged 3 of 7 days · 2,160 Cal in total · avg 720 · protein target hit 0 days · trend −0.6 kg.", review.summary)
        assertEquals("Nothing logged this week yet.", WeeklyReview.make(AppData(), Goals(), ending = day0.plusDays(6)).summary)
    }

    @Test fun checkIn() {
        val now = LocalDate.of(2026, 9, 29).atTime(9, 0).atZone(zone).toInstant()
        fun ago(n: Int) = now.atZone(zone).minusDays(n.toLong()).toInstant()
        val meal = Food(id = "meal", name = "Meal", kj = 8368.0, cal = 2000.0, p = 150.0)
        var data = AppData(
            logs = (1..28).associate { dayKey(ago(it)) to listOf(LogEntry(name = "Day", items = listOf(Portion(food = meal)), time = ago(it))) },
            weights = (0..40).map { WeightEntry(date = ago(40 - it), kg = 85 - it * 0.5 / 7) },
        )
        val goals = Goals(values = mapOf("cal" to 2200.0, "p" to 150.0, "c" to 200.0, "f" to 70.0))
        assertEquals(0, CheckIn.readiness(data, now).daysNeeded)
        val suggestion = CheckIn.suggestion(data, goals, -0.5, now)!!
        assertTrue(suggestion.maintenance in 2400.0..2700.0 && suggestion.weeklyChange!! < -0.3)
        assertTrue(suggestion.calories % 10 == 0.0 && abs(suggestion.calories - (suggestion.maintenance - 550)) < 10)
        assertTrue(suggestion.values["p"] == null && suggestion.values["c"]!! > 0 &&
            abs(suggestion.values["c"]!! * 4 + suggestion.values["f"]!! * 9 - (suggestion.calories - 600)) < 10)
        val gain = CheckIn.suggestion(data, goals, 0.5, now)!!
        assertTrue(gain.limitedByStep && gain.calories == 2500.0)
        val floor = CheckIn.suggestion(data, goals.copy(values = goals.values + ("cal" to 1250.0)), -1.0, now)!!
        assertTrue(floor.calories >= CheckIn.LOWEST && floor.paceIsFast && !suggestion.paceIsFast)
        assertNull(CheckIn.suggestion(AppData(), goals, 0.0, now))
        assertEquals(10, CheckIn.readiness(AppData(), now).daysNeeded)
        assertTrue(CheckIn.isDue(data, now))
        data = CheckIn.record(suggestion, true, data, now)
        assertTrue(!CheckIn.isDue(data, ago(-6)) && CheckIn.isDue(data, ago(-7)))
        assertTrue(data.isValid && CheckIn.headline(suggestion).startsWith("You're losing"))
        data = data.copy(weightGoal = WeightGoal(75.0, 85.0, ago(40)))
        assertEquals(-0.5, CheckIn.pace(data, now), 0.0)
        data = data.copy(checkInPace = -0.25)
        assertEquals(-0.25, CheckIn.pace(data, now), 0.0)
        assertFalse(data.copy(checkInPace = -3.0).isValid)
    }

    @Test fun streaksStepsEnergyAndMeasurements() {
        assertEquals(3, TrackingStreak.best(setOf("2026-10-03", "2026-10-01", "2026-09-30", "2026-09-20")))
        assertEquals(3, TrackingStreak.best(setOf("2025-12-30", "2025-12-31", "2026-01-01", "2026-03-01")))
        assertEquals(3, TrackingStreak.best(setOf("2026-02-27", "2026-02-28", "2026-03-01")))
        val on = LocalDate.of(2026, 10, 3)
        assertEquals(1, TrackingStreak.count(setOf("2026-10-03", "2026-09-30"), on))
        assertEquals(2, TrackingStreak.count(setOf("2026-10-03", "2026-10-01", "2026-09-29"), on))
        assertEquals(0, TrackingStreak.count(setOf("2026-10-05"), on))

        assertTrue(Steps.goal(AppData()) == 8000.0 && Steps.text(6420.4) == "6,420" && Steps.progress(4000.0, 8000.0) == 0.5 && Steps.progress(9000.0, 8000.0) == 1.0)
        val stepDays = listOf("2026-10-10", "2026-10-11", "2026-10-12", "2026-10-13")
        val walked = Steps.summary(mapOf("2026-10-10" to 9000.0, "2026-10-11" to 0.0, "2026-10-12" to 5000.0), stepDays, 8000.0)
        assertTrue(walked.average == 7000.0 && walked.countedDays == 2 && walked.daysMet == 1 && walked.total == 14000.0 && walked.best == 9000.0)
        assertNull(Steps.summary(emptyMap(), stepDays, 8000.0).average)
        assertTrue(ActiveEnergy.text(412.4) == "412" && ActiveEnergy.text(1250.6) == "1,251")
        val d6 = day0.plusDays(6)
        assertEquals(300.0, ActiveEnergy.recentAverage(mapOf(dayKey(d6) to 700.0, dayKey(day0.plusDays(4)) to 300.0, dayKey(day0.plusDays(3)) to 500.0,
            dayKey(day0.plusDays(2)) to 100.0), d6)!!, 0.0)

        val entries = listOf(
            BodyMeasurement(date = day(0), values = mapOf("waist" to 90.0, "hips" to 100.0)),
            BodyMeasurement(date = day(7), values = mapOf("waist" to 88.5)),
            BodyMeasurement(date = day(14).plusSeconds(60), values = mapOf("waist" to 87.9)),
            BodyMeasurement(date = day(14), values = mapOf("waist" to 91.0, "wrist" to 17.0)),
        )
        val waist = BodyMeasurements.readings(entries, "waist")
        assertEquals(listOf(90.0, 88.5, 87.9), waist.map { it.cm })
        val change = BodyMeasurements.change(waist)!!
        near(-0.6, change.sinceLast!!); near(-2.1, change.sinceFirst!!)
        assertNull(BodyMeasurements.change(BodyMeasurements.readings(entries, "hips"))!!.sinceLast)
        assertNull(BodyMeasurements.change(emptyList()))
        assertEquals(listOf("waist", "hips", "wrist"), BodyMeasurements.sites(entries))
        assertTrue(BodyMeasurements.title("arm") == "Upper arm" && BodyMeasurements.title("wrist") == "Wrist")
        assertTrue(BodyMeasurements.signed(-3.54) == "−3.5 cm" && BodyMeasurements.signed(1.0) == "+1 cm" && BodyMeasurements.signed(0.01) == "no change")
    }
}
