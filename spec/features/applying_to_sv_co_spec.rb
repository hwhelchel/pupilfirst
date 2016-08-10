require 'rails_helper'

feature 'Applying to SV.CO' do
  # Things that are assumed to exist.
  let!(:application_stage_1) { create :application_stage, number: 1 }
  let!(:application_stage_2) { create :application_stage, number: 2 }
  let!(:other_university) { create :university, name: 'Other' }
  let(:instamojo_payment_request_id) { SecureRandom.hex }
  let(:long_url) { 'http://example.com/a/b' }
  let(:short_url) { 'http://example.com/a/b' }

  context 'when a batch is open for applications' do
    let!(:batch) { create :batch, application_stage: application_stage_1, application_stage_deadline: 15.days.from_now, next_stage_starts_on: 1.month.from_now }

    scenario 'user submits application and pays' do
      visit apply_path
      expect(page).to have_text('Did you complete registration once before?')

      # user fills the form and submits
      fill_in 'batch_application_team_lead_attributes_name', with: 'Jack Sparrow'
      fill_in 'batch_application_team_lead_attributes_email', with: 'elcapitan@thesea.com'
      fill_in 'batch_application_team_lead_attributes_email_confirmation', with: 'elcapitan@thesea.com'
      fill_in 'batch_application_team_lead_attributes_phone', with: '9876543210'
      fill_in 'batch_application_university_id', with: University.last.id
      fill_in 'batch_application_college', with: 'Random College'
      click_on 'Submit my application'

      # user must be at the payment page
      expect(page).to have_text('You now need to pay the application fee')

      # user must have recieved a 'Continue Application' email
      open_email('elcapitan@thesea.com')
      expect(current_email.subject).to eq('Continue application at SV.CO')

      # prepare for invoking payment
      batch_applicant = BatchApplicant.find_by(email: 'elcapitan@thesea.com')
      batch_application = batch_applicant.batch_applications.last

      # stubbing instamojo requests
      allow_any_instance_of(Instamojo).to receive(:create_payment_request).with(
        amount: batch_application.fee,
        buyer_name: batch_application.team_lead.name,
        email: batch_application.team_lead.email
      ).and_return(
        id: instamojo_payment_request_id,
        status: 'Pending',
        long_url: long_url,
        short_url: short_url
      )

      # user selects co-founder count and clicks pay
      select '2', from: 'application_stage_one_cofounder_count'
      expect(page).to have_text('You need to pay Rs. 3000')
      click_on 'Pay Fees Online'

      # uses must be re-directed to the payment's long_url
      expect(page.current_url).to eq(long_url)

      payment = Payment.last
      # ensure we got the right payment
      expect(payment.batch_application).to eq(batch_application)

      # mimic payment completion
      payment.update!(
        instamojo_payment_request_status: 'Completed',
        instamojo_payment_status: 'Credit',
        paid_at: Time.now
      )
      payment.batch_application.perform_post_payment_tasks!

      # user reaches stage/1/complete
      visit apply_stage_complete_path(stage_number: '1')
      expect(page).to have_text('your payment has been accepted')
    end

    context 'when an applied user returns' do
      # ready-to-use returning applicant and his application
      let(:batch_applicant) { create :batch_applicant }

      let!(:batch_application) do
        create :batch_application,
          batch: batch,
          application_stage: ApplicationStage.initial_stage,
          university_id: University.last.id,
          college: 'Random College',
          team_lead_id: batch_applicant.id
      end

      before do
        batch_application.batch_applicants << batch_applicant
      end

      scenario 'Returning applicant logs in' do
        # user signs in
        visit apply_path
        expect(page).to have_text('Did you complete registration once before?')

        click_on 'Sign In to Continue'
        expect(page).to have_text('Please supply your email address')

        fill_in 'batch_applicant_sign_in_email', with: batch_applicant.email
        click_on 'Resend link to resume application'

        # user must be told an email was sent
        expect(page).to have_text("Please use the link that we've mailed you to resume the application process")

        # user must have recieved a 'Continue Application' email
        open_email(batch_applicant.email)
        continue_path = apply_continue_path(token: batch_applicant.token, shared_device: false)
        expect(current_email.body).to have_text(continue_path)

        # user follows login link sent
        visit continue_path

        # user must be at the payment page
        expect(page).to have_text('You now need to pay the application fee')
      end
    end
  end
end
